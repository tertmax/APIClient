//
//  ViewController.swift
//  APIClient-Example
//
//  Created by Roman Kyrylenko on 1/23/18.
//  Copyright © 2018 Yalantis. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    @IBOutlet private var ipAddressTextField: UITextField!
    @IBOutlet private var dataTextView: UITextView!
    
    @IBAction private func findCurrentIP() {
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        
        ipServiceNetworkClient.execute(request: IPAddressRequest()) { [weak self] response in
            UIApplication.shared.isNetworkActivityIndicatorVisible = false

            switch response {
            case .success(let result):
                self?.display(ipAddress: result)
            case .failure(let error):
                self?.display(error: error)
            }
        }
    }
    
    @IBAction private func findData() {
        geoServiceNetworkClient.execute(request: IPAddressDataRequest(ipAddress: ipAddressTextField.text ?? "")) { [weak self] response in
            UIApplication.shared.isNetworkActivityIndicatorVisible = false

            switch response {
            case .success(let result):
                self?.display(data: result)
            case .failure(let error):
                self?.display(error: error)
            }
        }
    }
    
    private func display(error: Error) {
        dataTextView.text = error.localizedDescription
    }
    
    private func display(ipAddress: IPAddress) {
        ipAddressTextField.text = ipAddress.ip
    }
    
    private func display(data: LocationMetaData) {
        dataTextView.text = "\(data)"
    }
}

extension ViewController: NetworkClientInjectable {}
