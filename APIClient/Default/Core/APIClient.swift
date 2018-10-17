import Foundation

open class APIClient: NSObject, NetworkClient {
    
    public typealias HTTPResponse = (httpResponse: HTTPURLResponse, data: Data)
    
    private let requestExecutor: RequestExecutor
    private let deserializer: Deserializer
    private let plugins: [PluginType]
    
    // MARK: - Init
    
    public init(requestExecutor: RequestExecutor, deserializer: Deserializer = JSONDeserializer(), plugins: [PluginType] = [ErrorPreprocessorPlugin(errorPreprocessor: NetworkErrorProcessor())]) {
        self.requestExecutor = requestExecutor
        self.deserializer = deserializer
        self.plugins = plugins
    }
    
    // MARK: - NetworkClient
    
    @discardableResult
    public func execute<T>(request: APIRequest, parser: T, completion: @escaping (Result<T.Representation>) -> Void) -> Cancelable where T : ResponseParser {
        let resultProducer: (@escaping APIResultResponse) -> Cancelable = { completion in
            let request = self.prepare(request: request)
            self.willSend(request: request)
            return self.requestExecutor.execute(request: request, completion: completion)
        }
        
        return _execute(resultProducer, deserializer: self.deserializer, parser: parser, completion: completion)
    }
    
    @discardableResult
    public func execute<T>(request: MultipartAPIRequest, parser: T, completion: @escaping (Result<T.Representation>) -> Void) -> Cancelable where T: ResponseParser {
        let resultProducer: (@escaping APIResultResponse) -> Cancelable = { completion in
            guard let request = self.prepare(request: request) as? MultipartAPIRequest else {
                fatalError("Unexpected request type. Expected `MultipartAPIRequest`")
            }
            self.willSend(request: request)
            return self.requestExecutor.execute(multipartRequest: request, completion: completion)
        }
        return _execute(resultProducer, deserializer: self.deserializer, parser: parser, completion: completion)
    }
    
    @discardableResult
    public func execute<T>(request: DownloadAPIRequest, destinationFilePath: URL?, deserializer: Deserializer?, parser: T, completion: @escaping (Result<T.Representation>) -> Void) -> Cancelable where T: ResponseParser {
        let resultProducer: (@escaping APIResultResponse) -> Cancelable = { completion in
            guard let request = self.prepare(request: request) as? DownloadAPIRequest else {
                fatalError("Unexpected request type. Expected `MultipartAPIRequest`")
            }
            self.willSend(request: request)
            return self.requestExecutor.execute(downloadRequest: request, destinationPath: destinationFilePath, completion: completion)
        }
        return _execute(resultProducer, deserializer: self.deserializer, parser: parser, completion: completion)
    }
    
    private func _execute<T>(_ resultProducer: @escaping (@escaping APIResultResponse) -> Cancelable, deserializer: Deserializer, parser: T, completion: @escaping (Result<T.Representation>) -> Void) -> Cancelable where T: ResponseParser {
        return resultProducer { response in
            let validatedResult = self.validateResult(response)
            
            if let error = validatedResult.error {
                self.resolve(error: error, onResolved: { isResolved in
                    if isResolved {
                        _ = resultProducer { response in
                            self.proccessResponse(response: response, parser: parser, completion: completion)
                        }
                    } else {
                        self.proccessResponse(response: response, parser: parser, completion: completion)
                    }
                })
            } else {
                self.proccessResponse(response: response, parser: parser, completion: completion)
            }
        }
    }
    
    private func validateResult(_ result: Result<HTTPResponse>) -> Result<HTTPResponse> {
        if let response = result.value {
            self.didReceive(response)
            
            switch response.httpResponse.statusCode {
            case 200...299: return .success(response)
            default: return .failure(self.process(response) ?? NetworkError.unsatisfiedHeader(code: response.httpResponse.statusCode))
            }
        }
        return result
    }
    
    private func proccessResponse<T>(response: (Result<HTTPResponse>), parser: T, completion: @escaping (Result<T.Representation>) -> Void) where T: ResponseParser {
        
        let result = validateResult(response)
        
        if case let .failure(error) = result {
            let decoratedError = decorate(error: error)
            completion(.failure(decoratedError))
            return
        }
        
        completion(
            result
                .next(self.deserializer.deserialize)
                .next(parser.parse)
                .map(self.process)
        )
    }
}

// MARK: - Plugins support

private extension APIClient {
    
    func process<T>(result: T) -> T {
        return plugins.reduce(result) { $1.process($0) }
    }
    
    func resolve(error: Error, onResolved: @escaping (Bool) -> Void) {
        if let plugin = plugins.first(where: { $0.canResolve(error) }) {
            plugin.resolve(error, onResolved: onResolved)
        } else {
            onResolved(false)
        }
    }
    
    func didReceive(_ response: HTTPResponse) {
        plugins.forEach { $0.didReceive(response: response) }
    }
    
    func process(_ response: HTTPResponse) -> Error? {
        for plugin in plugins {
            if let error = plugin.processError(response) {
                return error
            }
        }
        return nil
    }
    
    func willSend(request: APIRequest) {
        plugins.forEach { $0.willSend(request) }
    }
    
    func prepare(request: APIRequest) -> APIRequest {
        return plugins.reduce(request) { $1.prepare($0) }
    }
    
    func decorate(error: Error) -> Error {
        return plugins.reduce(error) { $1.decorate($0) }
    }
}
