Pod::Spec.new do |s|
  s.name             = 'RFIDManagerSDK'
  s.version          = '2.0.1'
  s.summary          = 'Chainway RFIDManager xcframework for BLE UHF readers'
  s.homepage         = 'https://github.com/RFID-Devs/RFID-IOS-SDK'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'RFID-Devs' => 'https://github.com/RFID-Devs' }
  s.source           = { :path => '.' }
  s.ios.deployment_target = '14.0'
  s.vendored_frameworks = 'Frameworks/RFIDManager.xcframework'
  s.swift_version    = '5.0'
  s.frameworks       = 'CoreBluetooth'
end
