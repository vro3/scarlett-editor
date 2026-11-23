#!/usr/bin/env python3
"""Generate a disposable, serial-gated hardware XCTest target; never part of release schemes."""
import plistlib,sys
from pathlib import Path
from xml.sax.saxutils import escape
root=Path(__file__).resolve().parent.parent
serial=sys.argv[1]
assert serial.isalnum()
project=plistlib.loads((root/'ScarlettDirect.xcodeproj/project.pbxproj').read_bytes())
o=project['objects']; counter=0xF000

def obj(isa,**kw):
 global counter
 counter+=1; key=f'{counter:024X}'; o[key]=dict(isa=isa,**kw); return key

def configs(settings):
 refs=[obj('XCBuildConfiguration',name=n,buildSettings=settings) for n in ['Debug','Release']]
 return obj('XCConfigurationList',buildConfigurations=refs,defaultConfigurationIsVisible='0',defaultConfigurationName='Debug')

app=next(k for k,v in o.items() if v.get('isa')=='PBXNativeTarget' and v.get('name')=='ScarlettDirect')
for config in o[o[app]['buildConfigurationList']]['buildConfigurations']:
 o[config]['buildSettings'].update(ENABLE_TESTABILITY='YES',DEFINES_MODULE='YES',SWIFT_INSTALL_OBJC_HEADER='NO')
source=obj('PBXFileReference',path='HardwareTests/MixerHardwareTests.swift',lastKnownFileType='sourcecode.swift',sourceTree='<group>')
product=obj('PBXFileReference',path='MixerHardwareTests.xctest',explicitFileType='wrapper.cfbundle',sourceTree='BUILT_PRODUCTS_DIR')
settings=dict(DEVELOPMENT_TEAM='YOURTEAMID',CODE_SIGN_STYLE='Automatic',SDKROOT='iphoneos',SUPPORTED_PLATFORMS='iphoneos',IPHONEOS_DEPLOYMENT_TARGET='17.0',TARGETED_DEVICE_FAMILY='2',SWIFT_VERSION='5.0',SWIFT_OPTIMIZATION_LEVEL='-Onone',PRODUCT_BUNDLE_IDENTIFIER='com.performancepercussion.scarlettdirect.hardwaretests',PRODUCT_NAME='$(TARGET_NAME)',GENERATE_INFOPLIST_FILE='YES',TEST_HOST='$(BUILT_PRODUCTS_DIR)/ScarlettDirect.app/ScarlettDirect',BUNDLE_LOADER='$(TEST_HOST)',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks'])
phase=obj('PBXSourcesBuildPhase',buildActionMask='2147483647',files=[obj('PBXBuildFile',fileRef=source)],runOnlyForDeploymentPostprocessing='0')
dep=obj('PBXTargetDependency',target=app)
test=obj('PBXNativeTarget',name='MixerHardwareTests',productName='MixerHardwareTests',productReference=product,productType='com.apple.product-type.bundle.unit-test',buildConfigurationList=configs(settings),buildPhases=[phase],buildRules=[],dependencies=[dep])
p=o[project['rootObject']]; p['targets'].append(test); o[p['mainGroup']]['children'] += [source,product]
out=root/'ScarlettHardwareTests.xcodeproj'; out.mkdir(exist_ok=True); (out/'project.pbxproj').write_bytes(plistlib.dumps(project))
def ref(id,name,product): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{id}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:ScarlettHardwareTests.xcodeproj"/>'
scheme=f'''<?xml version="1.0" encoding="UTF-8"?><Scheme version="1.7">
<BuildAction parallelizeBuildables="NO" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{ref(test,'MixerHardwareTests','MixerHardwareTests.xctest')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="NO"><Testables><TestableReference skipped="NO">{ref(test,'MixerHardwareTests','MixerHardwareTests.xctest')}</TestableReference></Testables><EnvironmentVariables><EnvironmentVariable key="SCARLETT_TEST_SERIAL" value="{escape(serial)}" isEnabled="YES"/></EnvironmentVariables></TestAction></Scheme>'''
d=out/'xcshareddata/xcschemes'; d.mkdir(parents=True,exist_ok=True); (d/'MixerHardwareTests.xcscheme').write_text(scheme)
print(out)
