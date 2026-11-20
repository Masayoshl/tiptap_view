# For apps that still use CocoaPods; Swift Package Manager reads ios/tiptap_view/Package.swift instead.
Pod::Spec.new do |s|
  s.name             = 'tiptap_view'
  s.version          = '0.3.0'
  s.summary          = 'Shows and edits TipTap documents in Flutter through a WebView.'
  s.homepage         = 'https://github.com/Masayoshl/tiptap_view'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'tiptap_view' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'tiptap_view/Sources/tiptap_view/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
