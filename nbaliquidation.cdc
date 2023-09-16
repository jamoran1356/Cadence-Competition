import FungibleToken from "../contracts/FungibleToken.cdc"
import NonFungibleToken from "../contracts/NonFungibleToken.cdc"
import TopShot from "../contracts/TopShot.cdc"
import DapperUtilityCoin from "../contracts/DapperUtilityCoin.cdc"
import TopShotBundleMarket from "../contracts/TopShotBundleMarket.cdc"

pub contract nbaquicksale {

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

    //this function is to sell all your moments at floor price
    fun sellAtFloorPrice() {
        // Get the list of all moments in the collection
        let moments = self.ownerCollection.borrow()!.getMoments()
        // Get the floor price for each moment
        let floorPrices = moments.map(moment => TopShot.getFloorPrice(moment.id))
        // Create a bundle for each moment
        let bundles = moments.map(moment => Bundle(price: floorPrices[moment], tokenIDs: [moment.id]))
        // List all the bundles for sale
        for bundle in bundles {
            self.listForSale(tokenIDs: bundle.tokenIDs, price: bundle.price)
        }
    }

    /// This function is to accept all avalaibles offers for your moments.
    fun acceptOffer(bundleID: UInt64) {
        // Get the bundle
        let bundle = self.listings[bundleID]!
        // Get the offer
        let offer = TopShotBundleMarket.getOffer(bundleID)
        // Check if the offer is still valid
        if offer.expiration < getCurrentTime() {
            throw Error("Offer is no longer valid")
        }

        // Check if the offer is for the full price
        if offer.price != bundle.price {
            throw Error("Offer is not for the full price")
        }

        // Transfer the moments to the buyer
        self.ownerCollection.borrow()!.transferMoments(tokenIDs: bundle.tokenIDs, to: offer.buyer)

        // Transfer the funds to the seller
        DapperUtilityCoin.transfer(amount: offer.price, to: self.owner)

        // Remove the listing
        self.listings.remove(key: bundleID)

        // Emit the event
        emit BundlePurchased(id: bundleID, price: offer.price, seller: self.owner)
    }

        /// Publish a bundle for sale if there is no offer for it.
        fun publishIfNoOffer(bundleID: UInt64) {
            if !self.listings.contains(key: bundleID) {
                self.listForSale(tokenIDs: bundle.tokenIDs, price: bundle.price)
            }
        }
    }
}