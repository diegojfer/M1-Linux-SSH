//
//  VM.swift
//  M1-Linux-SSH
//
//  Created by Jacopo Mangiavacchi on 11/22/20.
//

import Foundation
import Virtualization

class VM: NSObject, VZVirtualMachineDelegate {
    let kernelURL: URL
    let initialRamdiskURL: URL
    let bootableImageURL: URL

    private var virtualMachine: VZVirtualMachine?
    
    private let readPipe = Pipe()
    private let writePipe = Pipe()
    
    init(kernelURL: URL, initialRamdiskURL: URL, bootableImageURL: URL) {
        self.kernelURL = kernelURL
        self.initialRamdiskURL = initialRamdiskURL
        self.bootableImageURL = bootableImageURL
    }
    
    func start() {
        let bootloader = VZLinuxBootLoader(kernelURL: kernelURL)
        bootloader.initialRamdiskURL = initialRamdiskURL
        bootloader.commandLine = "console=hvc0"
        
        let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
        
        serial.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: writePipe.fileHandleForReading,
            fileHandleForWriting: readPipe.fileHandleForWriting
        )

        let entropy = VZVirtioEntropyDeviceConfiguration()
        
        let memoryBalloon = VZVirtioTraditionalMemoryBalloonDeviceConfiguration()
        
        let blockAttachment: VZDiskImageStorageDeviceAttachment
        
        do {
            blockAttachment = try VZDiskImageStorageDeviceAttachment(
                url: bootableImageURL,
                readOnly: true
            )
        } catch {
            print("Failed to load bootableImage: \(error)")
            return
        }
        
        let blockDevice = VZVirtioBlockDeviceConfiguration(attachment: blockAttachment)
        
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.attachment = VZNATNetworkDeviceAttachment()
        
        let config = VZVirtualMachineConfiguration()
        config.bootLoader = bootloader
        config.cpuCount = 4
        config.memorySize = 2 * 1024 * 1024 * 1024
        config.entropyDevices = [entropy]
        config.memoryBalloonDevices = [memoryBalloon]
        config.serialPorts = [serial]
        config.storageDevices = [blockDevice]
        config.networkDevices = [networkDevice]
                
        do {
            try config.validate()
            
            let vm = VZVirtualMachine(configuration: config)
            vm.delegate = self
            self.virtualMachine = vm
            
            vm.start { result in
                switch result {
                case .success:
                    print("VM Started succesfully")
                    break
                case .failure(let error):
                    print("VM Failed: \(error)")
                }
            }
        } catch {
            print("Error: \(error)")
            return
        }
    }
    
    func stop() {
        if let virtualMachine = virtualMachine {
            do {
                try virtualMachine.requestStop()
            } catch {
                print("Failed to stop: \(error)")
            }
            self.virtualMachine = nil
        }
    }
    
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        print("Stopped")
    }
    
    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        print("Stopped with error: \(error)")
    }
}
