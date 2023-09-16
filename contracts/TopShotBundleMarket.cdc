import FungibleToken from "../contracts/FungibleToken.cdc"
import NonFungibleToken from "../contracts/NonFungibleToken.cdc"
import TopShot from "../contracts/TopShot.cdc"
import DapperUtilityCoin from "../contracts/DapperUtilityCoin.cdc"
import TopShotLocking from "../contracts/TopShotLocking.cdc"

pub contract TopShotBundleMarket {

    pub var totalBundles: UInt64

    pub event BundleListed(tokenIDs: [UInt64], price: UFix64, seller: Address?)
    pub event BundlePriceChanged(id: UInt64, newPrice: UFix64, seller: Address?)
    pub event BundlePurchased(id: UInt64, price: UFix64, seller: Address?)
    pub event BundleWithdrawn(id: UInt64, owner: Address?)

    pub let BundleMarketStoragePath: StoragePath
    pub let BundleMarketPublicPath: PublicPath

    pub struct Bundle {
        pub let price: UFix64
        pub let tokenIDs: [UInt64]

        init(price: UFix64, tokenIDs: [UInt64]) {
            self.price = price
            self.tokenIDs = tokenIDs
        }
    }

    pub resource interface SalePublic {
        pub var cutPercentage: UFix64
        pub fun purchase(bundleID: UInt64, buyTokens: @DapperUtilityCoin.Vault): @[TopShot.NFT]
        pub fun getBundleData(bundleID: UInt64): Bundle?
        pub fun getMomentDatasInBundle(bundleID: UInt64): [&TopShot.NFT?]?
        pub fun getIDs(): [UInt64]
    }

    pub resource SaleCollection: SalePublic {
        access(self) var ownerCollection: Capability<&TopShot.Collection>
        access(self) var listings: {UInt64: Bundle}
        access(self) var ownerCapability: Capability<&{FungibleToken.Receiver}>
        access(self) var beneficiaryCapability: Capability<&{FungibleToken.Receiver}>
        pub var cutPercentage: UFix64

        init (
            ownerCollection: Capability<&TopShot.Collection>,
            ownerCapability: Capability<&{FungibleToken.Receiver}>,
            beneficiaryCapability: Capability<&{FungibleToken.Receiver}>,
            cutPercentage: UFix64
        ) {
            pre {
                ownerCollection.check(): "Owner's Moment Collection Capability is invalid!"
                ownerCapability.check(): "Owner's Receiver Capability is invalid!"
                beneficiaryCapability.check(): "Beneficiary's Receiver Capability is invalid!" 
            }
            self.ownerCollection = ownerCollection
            self.ownerCapability = ownerCapability
            self.beneficiaryCapability = beneficiaryCapability
            self.listings = {}
            self.cutPercentage = cutPercentage
        }

        pub fun listForSale(tokenIDs: [UInt64], price: UFix64) {
            // make sure the user has all the tokenIDs
            for tokenID in tokenIDs {
                assert(
                    self.ownerCollection.borrow()!.borrowMoment(id: tokenID) != nil,
                    message: "Moment with ID ".concat(tokenID.toString()).concat(" does not exist in the owner's collection")
                )
            }
            // Set the listing
            self.listings[TopShotBundleMarket.totalBundles] = Bundle(price: price, tokenIDs: tokenIDs)
            emit BundleListed(tokenIDs: tokenIDs, price: price, seller: self.owner?.address)
            TopShotBundleMarket.totalBundles = TopShotBundleMarket.totalBundles + 1
        }

        pub fun cancelSale(bundleID: UInt64) {
            if self.listings[bundleID] == nil {
                return
            }

            // Remove the price from the prices dictionary
            self.listings.remove(key: bundleID)

            // Emit the event for withdrawing a moment from the Sale
            emit BundleWithdrawn(id: bundleID, owner: self.owner?.address)
        }

        /// purchase lets a user send tokens to purchase a Bundle that is for sale
        /// the purchased Bundle is returned to the transaction context that called it
        pub fun purchase(bundleID: UInt64, buyTokens: @DapperUtilityCoin.Vault): @[TopShot.NFT] {
            pre {
                self.listings[bundleID] == nil: "No bundle matching this ID for sale!"
            }

            let saleData: Bundle = self.listings[bundleID]!

            assert(
                buyTokens.balance == saleData.price,
                message: "Not enough tokens to buy the Bundle!"
            )

            // Take the cut of the tokens that the beneficiary gets from the sent tokens
            let beneficiaryCut <- buyTokens.withdraw(amount: saleData.price * self.cutPercentage)

            // Deposit it into the beneficiary's Vault
            self.beneficiaryCapability.borrow()!.deposit(from: <-beneficiaryCut)
            
            // Deposit the remaining tokens into the owners vault
            self.ownerCapability.borrow()!.deposit(from: <-buyTokens)

            emit BundlePurchased(id: bundleID, price: saleData.price, seller: self.owner?.address)

            // Return the purchased bundle
            let bundle: @[TopShot.NFT] <- []
            for id in saleData.tokenIDs {
                bundle.append(<- (self.ownerCollection.borrow()!.withdraw(withdrawID: id) as! @TopShot.NFT))
            }

            // remove the listing
            self.listings.remove(key: bundleID)

            return <- bundle
        }

        pub fun changeOwnerReceiver(_ newOwnerCapability: Capability<&{FungibleToken.Receiver}>) {
            pre {
                newOwnerCapability.borrow() != nil: 
                    "Owner's Receiver Capability is invalid!"
            }
            self.ownerCapability = newOwnerCapability
        }

        pub fun changeBeneficiaryReceiver(_ newBeneficiaryCapability: Capability<&{FungibleToken.Receiver}>) {
            pre {
                newBeneficiaryCapability.borrow() != nil: 
                    "Beneficiary's Receiver Capability is invalid!" 
            }
            self.beneficiaryCapability = newBeneficiaryCapability
        }

        pub fun getBundleData(bundleID: UInt64): Bundle? {
            return self.listings[bundleID]
        }

        pub fun getMomentDatasInBundle(bundleID: UInt64): [&TopShot.NFT?]? {
            if let bundle: Bundle = self.getBundleData(bundleID: bundleID) {
                let answer: [&TopShot.NFT?] = []
                for tokenID in bundle.tokenIDs {
                    let ref: &TopShot.NFT? = self.ownerCollection.borrow()!.borrowMoment(id: tokenID)
                    answer.append(ref)
                }
                return answer
            }
            return nil
        }

        /// getIDs returns an array of bundle IDs that are for sale
        pub fun getIDs(): [UInt64] {
            return self.listings.keys
        }
    }

    /// createCollection returns a new collection resource to the caller
    pub fun createSaleCollection(
        ownerCollection: Capability<&TopShot.Collection>,                    
        ownerCapability: Capability<&{FungibleToken.Receiver}>,
        beneficiaryCapability: Capability<&{FungibleToken.Receiver}>,
        cutPercentage: UFix64
    ): @SaleCollection {
        return <- create SaleCollection(ownerCollection: ownerCollection, ownerCapability: ownerCapability, beneficiaryCapability: beneficiaryCapability, cutPercentage: cutPercentage)
    }

    init() {
        self.totalBundles = 0
        self.BundleMarketStoragePath = /storage/TopShotBundleMarketSaleCollection
        self.BundleMarketPublicPath = /public/TopShotBundleMarketSaleCollection
    }
}