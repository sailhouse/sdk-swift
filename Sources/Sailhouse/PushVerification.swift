import Foundation
import CryptoKit

/// HMAC signature verification for push subscriptions
public struct PushVerification {
    /// The secret key used for HMAC verification
    private let secretKey: String
    
    /// Creates a new push verification instance
    /// - Parameter secretKey: The secret key to use for HMAC verification
    public init(secretKey: String) {
        self.secretKey = secretKey
    }
    
    /// Verifies an HMAC signature for push notification payload
    /// - Parameters:
    ///   - payload: The raw payload data
    ///   - signature: The HMAC signature to verify (should be hex-encoded)
    /// - Returns: True if the signature is valid, false otherwise
    public func verifySignature(payload: Data, signature: String) -> Bool {
        do {
            let computedSignature = try computeSignature(payload: payload)
            return computedSignature.lowercased() == signature.lowercased()
        } catch {
            return false
        }
    }
    
    /// Verifies an HMAC signature for push notification payload
    /// - Parameters:
    ///   - payload: The payload as a string
    ///   - signature: The HMAC signature to verify (should be hex-encoded)
    /// - Returns: True if the signature is valid, false otherwise
    public func verifySignature(payload: String, signature: String) -> Bool {
        guard let payloadData = payload.data(using: .utf8) else {
            return false
        }
        return verifySignature(payload: payloadData, signature: signature)
    }
    
    /// Computes the HMAC-SHA256 signature for the given payload
    /// - Parameter payload: The payload data to sign
    /// - Returns: The hex-encoded HMAC signature
    /// - Throws: An error if the signature computation fails
    public func computeSignature(payload: Data) throws -> String {
        guard let keyData = secretKey.data(using: .utf8) else {
            throw PushVerificationError.invalidSecretKey
        }
        
        let key = SymmetricKey(data: keyData)
        let signature = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        
        return signature.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Computes the HMAC-SHA256 signature for the given payload
    /// - Parameter payload: The payload string to sign
    /// - Returns: The hex-encoded HMAC signature
    /// - Throws: An error if the signature computation fails
    public func computeSignature(payload: String) throws -> String {
        guard let payloadData = payload.data(using: .utf8) else {
            throw PushVerificationError.invalidPayload
        }
        return try computeSignature(payload: payloadData)
    }
    
    /// Verifies a webhook request from Sailhouse
    /// - Parameters:
    ///   - headers: The HTTP headers from the webhook request
    ///   - body: The raw request body
    ///   - signatureHeader: The name of the header containing the signature (default: "x-sailhouse-signature")
    /// - Returns: True if the webhook is authentic, false otherwise
    public func verifyWebhook(
        headers: [String: String],
        body: Data,
        signatureHeader: String = "x-sailhouse-signature"
    ) -> Bool {
        guard let receivedSignature = headers[signatureHeader] else {
            return false
        }
        
        // Remove 'sha256=' prefix if present
        let signature = receivedSignature.hasPrefix("sha256=") 
            ? String(receivedSignature.dropFirst(7))
            : receivedSignature
        
        return verifySignature(payload: body, signature: signature)
    }
    
    /// Verifies a webhook request from Sailhouse
    /// - Parameters:
    ///   - headers: The HTTP headers from the webhook request
    ///   - body: The request body as a string
    ///   - signatureHeader: The name of the header containing the signature (default: "x-sailhouse-signature")
    /// - Returns: True if the webhook is authentic, false otherwise
    public func verifyWebhook(
        headers: [String: String],
        body: String,
        signatureHeader: String = "x-sailhouse-signature"
    ) -> Bool {
        guard let bodyData = body.data(using: .utf8) else {
            return false
        }
        return verifyWebhook(headers: headers, body: bodyData, signatureHeader: signatureHeader)
    }
}

/// Errors that can occur during push verification
public enum PushVerificationError: Error {
    /// The secret key is invalid
    case invalidSecretKey
    
    /// The payload is invalid
    case invalidPayload
    
    /// The signature is malformed
    case malformedSignature
}

/// Extension to provide convenient verification methods
public extension PushVerification {
    /// Creates a verification instance from environment variable
    /// - Parameter environmentVariable: The name of the environment variable containing the secret (default: "SAILHOUSE_WEBHOOK_SECRET")
    /// - Returns: A PushVerification instance if the environment variable exists
    static func fromEnvironment(
        environmentVariable: String = "SAILHOUSE_WEBHOOK_SECRET"
    ) -> PushVerification? {
        guard let secret = ProcessInfo.processInfo.environment[environmentVariable],
              !secret.isEmpty else {
            return nil
        }
        return PushVerification(secretKey: secret)
    }
}

/// Middleware for webhook verification in web frameworks
public struct WebhookVerificationMiddleware {
    /// The push verification instance
    private let verification: PushVerification
    
    /// Creates a new webhook verification middleware
    /// - Parameter verification: The push verification instance to use
    public init(verification: PushVerification) {
        self.verification = verification
    }
    
    /// Verifies a webhook request and calls the handler if verification succeeds
    /// - Parameters:
    ///   - headers: The HTTP headers from the request
    ///   - body: The raw request body
    ///   - handler: The handler to call if verification succeeds
    /// - Returns: True if verification succeeded and handler was called, false otherwise
    public func verifyAndHandle(
        headers: [String: String],
        body: Data,
        handler: (Data) throws -> Void
    ) rethrows -> Bool {
        guard verification.verifyWebhook(headers: headers, body: body) else {
            return false
        }
        
        try handler(body)
        return true
    }
    
    /// Verifies a webhook request and calls the handler if verification succeeds
    /// - Parameters:
    ///   - headers: The HTTP headers from the request
    ///   - body: The request body as a string
    ///   - handler: The handler to call if verification succeeds
    /// - Returns: True if verification succeeded and handler was called, false otherwise
    public func verifyAndHandle(
        headers: [String: String],
        body: String,
        handler: (String) throws -> Void
    ) rethrows -> Bool {
        guard verification.verifyWebhook(headers: headers, body: body) else {
            return false
        }
        
        try handler(body)
        return true
    }
}