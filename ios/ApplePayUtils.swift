//
//  ApplePayUtils.swift
//  stripe-react-native
//
//  Created by Charles Cruzan on 6/27/22.
//

import Foundation
import StripePaymentSheet

class ApplePayUtils {
    
    internal class func createPaymentRequest(
        merchantIdentifier: String?,
        params: NSDictionary
    ) -> (error: NSDictionary?, paymentRequest: PKPaymentRequest?) {
        guard let merchantIdentifier = merchantIdentifier else {
            return (Errors.createError(ErrorType.Failed, "You must provide merchantIdentifier"), nil)
        }

        if let additionalEnabledNetworks = params["additionalEnabledNetworks"] as? [String] {
            do {
                StripeAPI.additionalEnabledApplePayNetworks = try ApplePayUtils.mapToArrayOfPaymentNetworks(arrayOfStrings: additionalEnabledNetworks)
            } catch {
                return (Errors.createError(ErrorType.Failed, error.localizedDescription), nil)
            }
        } else if (params["jcbEnabled"] as? Bool == true) {
            StripeAPI.additionalEnabledApplePayNetworks = [.JCB]
        }

        guard let summaryItems = params["cartItems"] as? NSArray else {
            return (Errors.createError(ErrorType.Failed, "You must provide the items for purchase"), nil)
        }
        guard let countryCode = ((params.object(forKey: "merchantCountryCode") != nil) ? params["merchantCountryCode"] : params["country"]) as? String else {
            return (Errors.createError(ErrorType.Failed, "You must provide the country"), nil)
        }
        guard let currencyCode = ((params.object(forKey: "currencyCode") != nil) ? params["currencyCode"] : params["currency"]) as? String else {
            return (Errors.createError(ErrorType.Failed, "You must provide the payment currency"), nil)
        }

        let paymentRequest = StripeAPI.paymentRequest(withMerchantIdentifier: merchantIdentifier, country: countryCode, currency: currencyCode)

        let requiredShippingAddressFields = params["requiredShippingAddressFields"] as? NSArray ?? NSArray()
        let requiredBillingContactFields = params["requiredBillingContactFields"] as? NSArray ?? NSArray()
        let shippingMethods = params["shippingMethods"] as? NSArray ?? NSArray()

        paymentRequest.requiredShippingContactFields = Set(requiredShippingAddressFields.map {
            Mappers.mapToPKContactField(field: $0 as! String)
        })

        paymentRequest.requiredBillingContactFields = Set(requiredBillingContactFields.map {
            Mappers.mapToPKContactField(field: $0 as! String)
        })

        paymentRequest.shippingMethods = Mappers.mapToShippingMethods(shippingMethods: shippingMethods)

        do {
            paymentRequest.paymentSummaryItems = try ApplePayUtils
                .buildPaymentSummaryItems(items: summaryItems as? [[String : Any]])
        } catch  {
            return (Errors.createError(ErrorType.Failed, error.localizedDescription), nil)
        }
        return (nil, paymentRequest)
    }
    
    @available(iOS 15.0, *)
    internal class func createDeferredPaymentSummaryItem(item: [String : Any]) throws -> PKPaymentSummaryItem {
        let label = item["label"] as? String ?? ""
        let amount = NSDecimalNumber(string: item["amount"] as? String ?? "")
        
        let deferredItem = PKDeferredPaymentSummaryItem(
            label: label,
            amount: amount
        )
        guard let date = item["deferredDate"] as? Double else {
            throw ApplePayUtilsError.missingParameter(label, "deferredDate")
        }
        deferredItem.deferredDate = Date(timeIntervalSince1970: date)
        return deferredItem
    }
    
    @available(iOS 15.0, *)
    internal class func createRecurringPaymentSummaryItem(item: [String : Any]) throws -> PKPaymentSummaryItem {
        let label = item["label"] as? String ?? ""
        let amount = NSDecimalNumber(string: item["amount"] as? String ?? "")
        
        let recurringItem = PKRecurringPaymentSummaryItem(
            label: label,
            amount: amount
        )
        guard let intervalCount = item["intervalCount"] as? Int else {
            throw ApplePayUtilsError.missingParameter(label, "intervalCount")
        }
        recurringItem.intervalCount = intervalCount
        recurringItem.intervalUnit = try mapToIntervalUnit(intervalString: item["intervalUnit"] as? String)
        if let startDate = item["startDate"] as? Double {
            recurringItem.startDate = Date(timeIntervalSince1970: startDate)
        }
        if let endDate = item["endDate"] as? Double {
            recurringItem.endDate = Date(timeIntervalSince1970: endDate)
        }
        return recurringItem
    }
    
    internal class func mapToIntervalUnit(intervalString: String?) throws -> NSCalendar.Unit {
        switch intervalString {
        case "minute":
            return NSCalendar.Unit.minute
        case "hour":
            return NSCalendar.Unit.hour
        case "day":
            return NSCalendar.Unit.day
        case "month":
            return NSCalendar.Unit.month
        case "year":
            return NSCalendar.Unit.year
        default:
            throw ApplePayUtilsError.invalidTimeInterval(intervalString ?? "null")
        }
    }
    
    internal class func createImmediatePaymentSummaryItem(item: [String : Any]) -> PKPaymentSummaryItem {
        let label = item["label"] as? String ?? ""
        let amount = NSDecimalNumber(string: item["amount"] as? String ?? "")
        
        return PKPaymentSummaryItem(
            label: label,
            amount: amount,
            type: item["isPending"] as? Bool ?? false ?
                PKPaymentSummaryItemType.pending : PKPaymentSummaryItemType.final
        )
    }
    
    public class func buildPaymentSummaryItems(items: [[String : Any]]?) throws -> [PKPaymentSummaryItem] {
        var paymentSummaryItems: [PKPaymentSummaryItem] = []
        if let items = items {
            for item in items {
                let paymentSummaryItem = try buildPaymentSummaryItem(item: item)
                paymentSummaryItems.append(paymentSummaryItem)
            }
        }
        
        return paymentSummaryItems
    }
    
    internal class func buildPaymentSummaryItem(item: [String : Any]) throws -> PKPaymentSummaryItem {
        switch item["paymentType"] as? String {
        case "Deferred":
            if #available(iOS 15.0, *) {
                return try createDeferredPaymentSummaryItem(item: item)
            } else {
                return createImmediatePaymentSummaryItem(item: item)
            }
        case "Recurring":
            if #available(iOS 15.0, *) {
                return try createRecurringPaymentSummaryItem(item: item)
            } else {
                return createImmediatePaymentSummaryItem(item: item)
            }
        case "Immediate":
            return createImmediatePaymentSummaryItem(item: item)
        default:
            throw ApplePayUtilsError.invalidCartSummaryItemType(item["paymentType"] as? String ?? "null")
        }
    }
    
    internal class func mapToArrayOfPaymentNetworks(arrayOfStrings: [String]) throws -> [PKPaymentNetwork] {
        let validNetworks: [PKPaymentNetwork?] = try arrayOfStrings.map { networkString in
            switch networkString {
            case "amex": return PKPaymentNetwork.amex
            case "barcode": if #available(iOS 14.0, *) {
                return PKPaymentNetwork.barcode
            } else {
                return nil
            }
            case "cartesBancaires": return PKPaymentNetwork.cartesBancaires
            case "chinaUnionPay": return PKPaymentNetwork.chinaUnionPay
            case "dankort": if #available(iOS 15.1, *) {
                return PKPaymentNetwork.dankort
            } else {
                return nil
            }
            case "discover": return PKPaymentNetwork.discover
            case "eftpos": return PKPaymentNetwork.eftpos
            case "elo": if #available(iOS 12.1.1, *) {
                return PKPaymentNetwork.elo
            } else {
                return nil
            }
            case "girocard": if #available(iOS 14.0, *) {
                return PKPaymentNetwork.girocard
            } else {
                return nil
            }
            case "idCredit": return PKPaymentNetwork.idCredit
            case "interac": return PKPaymentNetwork.interac
            case "JCB": return PKPaymentNetwork.JCB
            case "mada": if #available(iOS 12.1.1, *) {
                return PKPaymentNetwork.mada
            } else {
                return nil
            }
            case "maestro": return PKPaymentNetwork.maestro
            case "masterCard": return PKPaymentNetwork.masterCard
            case "mir": if #available(iOS 14.5, *) {
                return PKPaymentNetwork.mir
            } else {
                return nil
            }
            case "nanaco": if #available(iOS 15.0, *) {
                return PKPaymentNetwork.nanaco
            } else {
                return nil
            }
            case "privateLabel": return PKPaymentNetwork.privateLabel
            case "quicPay": return PKPaymentNetwork.quicPay
            case "suica": return PKPaymentNetwork.suica
            case "visa": return PKPaymentNetwork.visa
            case "vPay": return PKPaymentNetwork.vPay
            case "waon": if #available(iOS 15.0, *) {
                return PKPaymentNetwork.waon
            } else {
                return nil
            }
            default:
                throw ApplePayUtilsError.invalidPaymentNetwork(networkString)
            }
        }
        return validNetworks.compactMap { $0 }
    }
    
    public class func buildPaymentSheetApplePayConfig(
        merchantIdentifier: String?,
        merchantCountryCode: String?,
        paymentSummaryItems: [[String : Any]]?
    ) throws -> PaymentSheet.ApplePayConfiguration {
        guard let merchantId = merchantIdentifier else {
            throw ApplePayUtilsError.missingMerchantId
        }
        guard let countryCode = merchantCountryCode else {
            throw ApplePayUtilsError.missingCountryCode
        }
        let paymentSummaryItems = try ApplePayUtils.buildPaymentSummaryItems(
            items: paymentSummaryItems
        )
        return PaymentSheet.ApplePayConfiguration.init(
            merchantId: merchantId,
            merchantCountryCode: countryCode,
            paymentSummaryItems:paymentSummaryItems.count > 0 ? paymentSummaryItems : nil
        )
    }
}

enum ApplePayUtilsError : Error, Equatable {
    case invalidCartSummaryItemType(String)
    case missingParameter(String, String)
    case invalidTimeInterval(String)
    case invalidPaymentNetwork(String)
    case missingMerchantId
    case missingCountryCode
}
    
extension ApplePayUtilsError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCartSummaryItemType(let type):
            return "Failed to ceate Apple Pay summary item. Expected `type` to be one of 'Immediate', 'Recurring', or 'Deferred', but received: \(type)"
        case .missingParameter(let label, let parameter):
            return "Failed to create Apple Pay summary item with label: \(label). The \(parameter) item parameter is required, but none was provided."
        case .invalidTimeInterval(let providedInterval):
            return "Failed to create Apple Pay summary item. \(providedInterval) is not a valid timeInterval, must be one of: minute, hour, day, month, or year."
        case .invalidPaymentNetwork(let network):
            return "Failed to create Apple Pay summary item. \(network) is not a valid/supported payment network."
        case .missingMerchantId:
            return "`merchantIdentifier` is required, but none was found. Ensure you are passing this to initStripe your StripeProvider."
        case .missingCountryCode:
            return "`merchantCountryCode` is a required param, but was not provided."
        }
    }
}
