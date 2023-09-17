import FungibleToken from "contracts/FungibleToken.cdc"
import NonFungibleToken from "contracts/NonFungibleToken.cdc"
import TopShot from "contracts/TopShot.cdc"
import DapperUtilityCoin from "contracts/DapperUtilityCoin.cdc"
import TopShotBundleMarket from "contracts/TopShotBundleMarket.cdc"

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
    // Update to check the best offer price, and to confirm the total 
    // amount to receive before accept the offers

    /* Update
    This feature allow user to keep some moments in the account
    using this let excludedMoments = [67890, 101112]
    and check if the moment has offer. Shows the user the estimated 
    value of the account and how much will get cashing out the moments
     */   
    fun acceptOffer(bundleID: UInt64, excludedMoments: [UInt64]) {

       // Get the bundle
        let bundle = self.listings[bundleID]!

        // Get the offer
        let offer = TopShotBundleMarket.getOffer(bundleID)

        // Check if the offer is still valid
        if offer.expiration < getCurrentTime() {
            throw Error("Offer is no longer valid")
        }

        // Check if the offer is for the full price or greater than the minimum offer
        if offer.price < bundle.price && !acceptAnyOffer {
            throw Error("Offer is not for the full price or doesn't meet the minimum offer requirement")
        }

        // Get the list of all offers for the bundle
        let offers = TopShotBundleMarket.getOffers(bundleID)

        // Create an array to store the moments with offers
        var momentsWithOffers: [UInt64] = []

        // Create an array to store the moments without offers
        var momentsNoOffer: [UInt64] = []

        // Check if there is an offer for each included moment
        // I created 2 arrays, one to store all the moments 
        // with offer and the other to store those without offer
        for tokenID in bundle.tokenIDs.filter(tokenID => !excludedMoments.contains(tokenID)) {
            if (TopShotBundleMarket.hasOffer(tokenID)) {
                momentsWithOffers.append(tokenID)
            } else {
                momentsNoOffer.append(tokenID)
            }
        }

        // Calculate the total value of the offer
        let totalValue = offer.price * momentsWithOffers.length

        // Show the user the offer information
        // Here the user will be able to decide
        // if wants to proceed with the moments 
        // sale by accepting the amount and the 
        // offers
        let message = """
            You are about to accept an offer for a bundle of ${momentsWithOffers.length} moments with a total value of ${totalValue}.

            Excluded moments: ${excludedMoments.length}
            Moments with offers: ${momentsWithOffers.length}
            Moments without offers: ${momentsNoOffer.length}

            Are you sure you want to proceed?
        """

        if !askConfirmation(message) {
            return
        }
       // if seller confirms the contract proceed to accep
       // all the offers and start with the offer acceptance
       // Transfer the moments to the buyer
        self.ownerCollection.borrow()!.transferMoments(tokenIDs: momentsWithOffers, to: offer.buyer)

        // Transfer the funds to the seller
        DapperUtilityCoin.transfer(amount: offer.price, to: self.owner)

        // Remove the listing
        self.listings.remove(key: bundleID)

        // Emit the event
        emit BundlePurchased(id: bundleID, price: offer.price, seller: self.owner)

        // Publish the moments that don't have offers for sale
        for tokenID in momentsNoOffer {
            self.publishIfNoOffer(tokenID)
        }
       
    }

        /// Publish a bundle for sale if there is no offer for it.
        fun publishIfNoOffer(bundleID: UInt64) {
            if !self.listings.contains(key: bundleID) {
                self.listForSale(tokenIDs: bundle.tokenIDs, price: bundle.price)
            }
        }
    }
}