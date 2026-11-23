#!/usr/bin/env python3
"""Generate a small, auditable Xcode project using standard PBX objects."""
from pathlib import Path
import plistlib
root=Path(__file__).resolve().parent.parent
objects={}
def obj(isa,**fields):
 key=f'{len(objects)+1:024X}'; objects[key]={'isa':isa,**fields}; return key
def file(path,kind): return obj('PBXFileReference',path=path,lastKnownFileType=kind,sourceTree='<group>')
def build(ref): return obj('PBXBuildFile',fileRef=ref)
def configs(settings):
 refs=[]
 for name in ['Debug','Release']:
  refs.append(obj('XCBuildConfiguration',name=name,buildSettings=dict(settings,SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG' if name=='Debug' else '',SWIFT_OPTIMIZATION_LEVEL='-Onone' if name=='Debug' else '-O')))
 return obj('XCConfigurationList',buildConfigurations=refs,defaultConfigurationIsVisible='0',defaultConfigurationName='Debug')
appFiles=[file('App/'+name,'sourcecode.swift') for name in ['ScarlettDirectApp.swift','RoutingView.swift','RecoveryStore.swift','EditorStyle.swift','MixerState.swift','MixerControl.swift','MixerPanel.swift']]
resources=[file('App/Fonts/AtkinsonHyperlegibleNext[wght].ttf','file')]
driverFiles=[file('Driver/'+n,t) for n,t in [('ScarlettDriver.cpp','sourcecode.cpp.cpp'),('ScarlettDriver.iig','sourcecode.iig'),('ScarlettClient.cpp','sourcecode.cpp.cpp'),('ScarlettClient.iig','sourcecode.iig'),('ScarlettBootstrap.cpp','sourcecode.cpp.cpp'),('ScarlettBootstrap.iig','sourcecode.iig')]]
shared=file('Shared/Protocol.hpp','sourcecode.cpp.h')
appProduct=obj('PBXFileReference',path='ScarlettDirect.app',explicitFileType='wrapper.application',sourceTree='BUILT_PRODUCTS_DIR')
driverProduct=obj('PBXFileReference',path='com.performancepercussion.scarlettdirect.driver.dext',explicitFileType='wrapper.driver-extension',sourceTree='BUILT_PRODUCTS_DIR')
products=obj('PBXGroup',name='Products',children=[appProduct,driverProduct],sourceTree='<group>')
group=obj('PBXGroup',children=appFiles+resources+driverFiles+[shared,products],sourceTree='<group>')
def phase(isa,refs): return obj(isa,buildActionMask='2147483647',files=[build(r) for r in refs],runOnlyForDeploymentPostprocessing='0')
common={'DEVELOPMENT_TEAM':'YOURTEAMID','CODE_SIGN_STYLE':'Automatic','CODE_SIGN_IDENTITY':'Apple Development','CURRENT_PROJECT_VERSION':'15','MARKETING_VERSION':'0.1','CLANG_CXX_LANGUAGE_STANDARD':'c++17','CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0','HEADER_SEARCH_PATHS':'$(SRCROOT)/Shared'}
driverSettings=dict(common,SDKROOT='driverkit',SUPPORTED_PLATFORMS='driverkit',DRIVERKIT_DEPLOYMENT_TARGET='23.0',PRODUCT_BUNDLE_IDENTIFIER='com.performancepercussion.scarlettdirect.driver',PRODUCT_NAME='$(PRODUCT_BUNDLE_IDENTIFIER)',INFOPLIST_FILE='Driver/Info.plist',CODE_SIGN_ENTITLEMENTS='Driver/Driver.entitlements',SKIP_INSTALL='YES',OTHER_LDFLAGS=['-framework','DriverKit','-framework','USBDriverKit'])
driver=obj('PBXNativeTarget',name='ScarlettDriver',productName='ScarlettDriver',productReference=driverProduct,productType='com.apple.product-type.driver-extension',buildConfigurationList=configs(driverSettings),buildPhases=[phase('PBXHeadersBuildPhase',[]),phase('PBXSourcesBuildPhase',driverFiles),phase('PBXFrameworksBuildPhase',[])],buildRules=[],dependencies=[])
dependency=obj('PBXTargetDependency',target=driver)
embed=phase('PBXCopyFilesBuildPhase',[driverProduct]); objects[embed].update(name='Embed Driver',dstPath='$(SYSTEM_EXTENSIONS_FOLDER_PATH)',dstSubfolderSpec='16')
for b in objects[embed]['files']: objects[b]['settings']={'ATTRIBUTES':['CodeSignOnCopy','RemoveHeadersOnCopy']}
appSettings=dict(common,SWIFT_OBJC_BRIDGING_HEADER='App/Bridge.h',SDKROOT='iphoneos',SUPPORTED_PLATFORMS='iphoneos',IPHONEOS_DEPLOYMENT_TARGET='17.0',TARGETED_DEVICE_FAMILY='2',PRODUCT_BUNDLE_IDENTIFIER='com.performancepercussion.scarlettdirect',PRODUCT_NAME='ScarlettDirect',INFOPLIST_FILE='App/Info.plist',CODE_SIGN_ENTITLEMENTS='App/App.entitlements',OTHER_LDFLAGS=['-framework','IOKit'],LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks'])
appSettings['CURRENT_PROJECT_VERSION']='29'
app=obj('PBXNativeTarget',name='ScarlettDirect',productName='ScarlettDirect',productReference=appProduct,productType='com.apple.product-type.application',buildConfigurationList=configs(appSettings),buildPhases=[phase('PBXResourcesBuildPhase',resources),phase('PBXSourcesBuildPhase',appFiles),phase('PBXFrameworksBuildPhase',[]),embed],buildRules=[],dependencies=[dependency])
project=obj('PBXProject',attributes={'LastUpgradeCheck':'2630'},buildConfigurationList=configs({}),compatibilityVersion='Xcode 14.0',developmentRegion='en',knownRegions=['en','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[app,driver])
p=root/'ScarlettDirect.xcodeproj'; p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_bytes(plistlib.dumps({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project}))
base={'CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'$(PRODUCT_BUNDLE_PACKAGE_TYPE)','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)'}
appInfo=dict(base,UIAppFonts=['AtkinsonHyperlegibleNext[wght].ttf'],CFBundleDisplayName='Scarlett Direct',UILaunchScreen={},UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],UIRequiredDeviceCapabilities=['arm64'])
personality={'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleIdentifierKernel':'com.apple.kpi.iokit','IOClass':'IOUserService','IOProviderClass':'IOUSBHostInterface','IOUserClass':'ScarlettDriver','IOUserServerName':'$(PRODUCT_BUNDLE_IDENTIFIER)','idVendor':0x1235,'idProduct':0x8212,'bConfigurationValue':1,'bInterfaceNumber':3,'bInterfaceClass':255,'UserClientProperties':{'IOClass':'IOUserUserClient','IOUserClass':'ScarlettClient'}}
bootstrap={'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleIdentifierKernel':'com.apple.kpi.iokit','IOClass':'IOUserService','IOProviderClass':'IOUserResources','IOResourceMatch':'IOKit','IOMatchCategory':'com.performancepercussion.scarlettdirect.diagnostic','IOUserClass':'ScarlettBootstrap','IOUserServerName':'$(PRODUCT_BUNDLE_IDENTIFIER)'}
driverInfo=dict(base,IOKitPersonalities={'ScarlettDriver':personality,'ScarlettBootstrap':bootstrap},OSBundleUsageDescription='Direct routing control for Scarlett 4i4 3rd Gen.')
for path,data in [('App/Info.plist',appInfo),('Driver/Info.plist',driverInfo),('App/App.entitlements',{'com.apple.developer.driverkit.communicates-with-drivers':True}),('Driver/Driver.entitlements',{'com.apple.developer.driverkit':True,'com.apple.developer.driverkit.transport.usb':[{'idVendor':0x1235}]})]:
 (root/path).write_bytes(plistlib.dumps(data))
print(p)
