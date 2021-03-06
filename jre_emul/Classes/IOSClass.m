// Copyright 2011 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//
//  IOSClass.m
//  JreEmulation
//
//  Created by Tom Ball on 10/18/11.
//

#import "IOSClass.h"
#import "J2ObjC_source.h"

#import "FastPointerLookup.h"
#import "IOSArrayClass.h"
#import "IOSConcreteClass.h"
#import "IOSMappedClass.h"
#import "IOSObjectArray.h"
#import "IOSPrimitiveArray.h"
#import "IOSPrimitiveClass.h"
#import "IOSProtocolClass.h"
#import "IOSProxyClass.h"
#import "IOSReflection.h"
#import "J2ObjC_icu.h"
#import "NSCopying+JavaCloneable.h"
#import "NSException+JavaThrowable.h"
#import "NSNumber+JavaNumber.h"
#import "NSObject+JavaObject.h"
#import "NSString+JavaString.h"
#import "com/google/j2objc/ReflectionStrippedError.h"
#import "java/lang/AssertionError.h"
#import "java/lang/ClassCastException.h"
#import "java/lang/ClassLoader.h"
#import "java/lang/ClassNotFoundException.h"
#import "java/lang/Enum.h"
#import "java/lang/InstantiationException.h"
#import "java/lang/NoSuchFieldException.h"
#import "java/lang/NoSuchMethodException.h"
#import "java/lang/NullPointerException.h"
#import "java/lang/Package.h"
#import "java/lang/annotation/Annotation.h"
#import "java/lang/annotation/Inherited.h"
#import "java/lang/reflect/Constructor.h"
#import "java/lang/reflect/Field.h"
#import "java/lang/reflect/Method.h"
#import "java/lang/reflect/Modifier.h"
#import "java/lang/reflect/TypeVariable.h"
#import "java/util/Enumeration.h"
#import "java/util/Properties.h"
#import "libcore/reflect/AnnotatedElements.h"
#import "libcore/reflect/GenericSignatureParser.h"
#import "libcore/reflect/Types.h"

#import "objc/message.h"
#import "objc/runtime.h"

#define IOSClass_serialVersionUID 3206093459760846163LL

@interface IOSClass () {
  const J2ObjcClassInfo *metadata_;
}
@end

J2OBJC_INITIALIZED_DEFN(IOSClass)

@implementation IOSClass

static NSDictionary *IOSClass_mappedClasses;

// Primitive class instances.
static IOSPrimitiveClass *IOSClass_byteClass;
static IOSPrimitiveClass *IOSClass_charClass;
static IOSPrimitiveClass *IOSClass_doubleClass;
static IOSPrimitiveClass *IOSClass_floatClass;
static IOSPrimitiveClass *IOSClass_intClass;
static IOSPrimitiveClass *IOSClass_longClass;
static IOSPrimitiveClass *IOSClass_shortClass;
static IOSPrimitiveClass *IOSClass_booleanClass;
static IOSPrimitiveClass *IOSClass_voidClass;

// Other commonly used instances.
static IOSClass *IOSClass_objectClass;

static IOSObjectArray *IOSClass_emptyClassArray;

#define PREFIX_MAPPING_RESOURCE @"/prefixes.properties"

// Package to prefix mappings, initialized in FindRenamedPackagePrefix().
static JavaUtilProperties *prefixMapping;

- (Class)objcClass {
  return nil;
}

- (Protocol *)objcProtocol {
  return nil;
}

+ (IOSClass *)byteClass {
  return IOSClass_byteClass;
}

+ (IOSClass *)charClass {
  return IOSClass_charClass;
}

+ (IOSClass *)doubleClass {
  return IOSClass_doubleClass;
}

+ (IOSClass *)floatClass {
  return IOSClass_floatClass;
}

+ (IOSClass *)intClass {
  return IOSClass_intClass;
}

+ (IOSClass *)longClass {
  return IOSClass_longClass;
}

+ (IOSClass *)shortClass {
  return IOSClass_shortClass;
}

+ (IOSClass *)booleanClass {
  return IOSClass_booleanClass;
}

+ (IOSClass *)voidClass {
  return IOSClass_voidClass;
}

- (instancetype)initWithClass:(Class)cls {
  if ((self = [super init])) {
    if (cls) {
      // Can't use respondsToSelector here because that will search superclasses.
      Method metadataMethod = JreFindClassMethod(cls, "__metadata");
      if (metadataMethod) {
        metadata_ = (const J2ObjcClassInfo *) method_invoke(cls, metadataMethod);
      }
    }
  }
  return self;
}

- (id)newInstance {
  // Per the JLS spec, throw an InstantiationException if the type is an
  // interface (no class_), array or primitive type (IOSClass types), or void.
  @throw AUTORELEASE([[JavaLangInstantiationException alloc] init]);
}

const J2ObjcClassInfo *IOSClass_GetMetadataOrFail(IOSClass *iosClass) {
  const J2ObjcClassInfo *metadata = iosClass->metadata_;
  if (metadata) {
    return metadata;
  }
  @throw create_ComGoogleJ2objcReflectionStrippedError_initWithIOSClass_(iosClass);
}

- (IOSClass *)getSuperclass {
  return nil;
}

- (id<JavaLangReflectType>)getGenericSuperclass {
  id<JavaLangReflectType> result = [self getSuperclass];
  if (!result) {
    return nil;
  }
  NSString *genericSignature = JreClassGenericString(metadata_);
  if (!genericSignature) {
    return result;
  }
  LibcoreReflectGenericSignatureParser *parser =
      [[LibcoreReflectGenericSignatureParser alloc]
       initWithJavaLangClassLoader:JavaLangClassLoader_getSystemClassLoader()];
  [parser parseForClassWithJavaLangReflectGenericDeclaration:self
                                                withNSString:genericSignature];
  result = [LibcoreReflectTypes getType:parser->superclassType_];
  [parser release];
  return result;
}

- (IOSClass *)getDeclaringClass {
  if ([self isPrimitive] || [self isArray] || [self isAnonymousClass] || [self isLocalClass]) {
    // Class.getDeclaringClass() javadoc, JVM spec 4.7.6.
    return nil;
  }
  IOSClass *enclosingClass = [self getEnclosingClass];
  while ([enclosingClass isAnonymousClass]) {
    enclosingClass = [enclosingClass getEnclosingClass];
  }
  return enclosingClass;
}

// Returns true if an object is an instance of this class.
- (jboolean)isInstance:(id)object {
  return false;
}

- (NSString *)getName {
  @throw AUTORELEASE([[JavaLangAssertionError alloc] initWithId:@"abstract method not overridden"]);
}

- (NSString *)getSimpleName {
  return [self getName];
}

- (NSString *)getCanonicalName {
  return [[self getName] stringByReplacingOccurrencesOfString:@"$" withString:@"."];
}

- (NSString *)objcName {
  @throw AUTORELEASE([[JavaLangAssertionError alloc] initWithId:@"abstract method not overridden"]);
}

- (jint)getModifiers {
  if (metadata_) {
    return metadata_->modifiers & JavaLangReflectModifier_classModifiers();
  } else {
    // All Objective-C classes and protocols are public by default.
    return JavaLangReflectModifier_PUBLIC;
  }
}

// Same as getModifiers, but returns all modifiers bits defined by the class.
- (jint)getAccessFlags {
  return metadata_ ? metadata_->modifiers : JavaLangReflectModifier_PUBLIC;
}

static void GetMethodsFromClass(IOSClass *iosClass, NSMutableDictionary *methods, bool publicOnly) {
  Class cls = iosClass.objcClass;
  if (!cls) {
    // Might be an array class.
    return;
  }
  const J2ObjcClassInfo *metadata = IOSClass_GetMetadataOrFail(iosClass);
  if (metadata->methodCount == 0) {
    return;
  }
  Protocol *protocol = iosClass.objcProtocol;
  unsigned int protocolMethodCount, instanceMethodCount, classMethodCount;
  struct objc_method_description *protocolMethods = NULL;
  Method *instanceMethods = NULL;
  if (protocol) {
    protocolMethods = protocol_copyMethodDescriptionList(protocol, YES, YES, &protocolMethodCount);
  } else {
    instanceMethods = class_copyMethodList(cls, &instanceMethodCount);
  }
  Method *classMethods = class_copyMethodList(object_getClass(cls), &classMethodCount);
  for (int i = 0; i < metadata->methodCount; i++) {
    const J2ObjcMethodInfo *methodInfo = &metadata->methods[i];
    if (!methodInfo->returnType) {  // constructor.
      continue;
    }
    if (publicOnly && (methodInfo->modifiers & JavaLangReflectModifier_PUBLIC) == 0) {
      continue;
    }
    SEL sel = JreMethodSelector(methodInfo);
    NSString *selector = NSStringFromSelector(sel);
    if ([methods valueForKey:selector]) {
      continue;
    }
    jboolean isStatic = (methodInfo->modifiers & JavaLangReflectModifier_STATIC) > 0;
    struct objc_method_description *methodDesc;
    if (isStatic) {
      methodDesc = JreFindMethodDescFromMethodList(sel, classMethods, classMethodCount);
    } else if (protocolMethods) {
      methodDesc = JreFindMethodDescFromList(sel, protocolMethods, protocolMethodCount);
    } else {
      methodDesc = JreFindMethodDescFromMethodList(sel, instanceMethods, instanceMethodCount);
    }
    if (!methodDesc) {
      continue;
    }
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:methodDesc->types];
    JavaLangReflectMethod *method =
        [JavaLangReflectMethod methodWithMethodSignature:signature
                                                selector:sel
                                                   class:iosClass
                                                isStatic:isStatic
                                                metadata:methodInfo];
    [methods setObject:method forKey:selector];
  }
  free(protocolMethods);
  free(instanceMethods);
  free(classMethods);
}

// Return the class and instance methods declared by the Java class.  Superclass
// methods are not included.
- (IOSObjectArray *)getDeclaredMethods {
  NSMutableDictionary *methodMap = [NSMutableDictionary dictionary];
  GetMethodsFromClass(self, methodMap, false);
  return [IOSObjectArray arrayWithNSArray:[methodMap allValues]
      type:JavaLangReflectMethod_class_()];
}

// Return the constructors declared by this class.  Superclass constructors
// are not included.
- (IOSObjectArray *)getDeclaredConstructors {
  return [IOSObjectArray arrayWithLength:0 type:JavaLangReflectConstructor_class_()];
}

static void GetAllMethods(IOSClass *cls, NSMutableDictionary *methodMap) {
  GetMethodsFromClass(cls, methodMap, true);

  // getMethods() returns unimplemented interface methods if the class is
  // abstract and default interface methods that aren't overridden.
  for (IOSClass *p in [cls getInterfacesInternal]) {
    GetAllMethods(p, methodMap);
  }

  while ((cls = [cls getSuperclass])) {
    GetAllMethods(cls, methodMap);
  }
}

// Return the methods for this class, including inherited methods.
- (IOSObjectArray *)getMethods {
  NSMutableDictionary *methodMap = [NSMutableDictionary dictionary];
  GetAllMethods(self, methodMap);
  return [IOSObjectArray arrayWithNSArray:[methodMap allValues]
                                     type:JavaLangReflectMethod_class_()];
}

// Return the constructors for this class, including inherited ones.
- (IOSObjectArray *)getConstructors {
  return [IOSObjectArray arrayWithLength:0 type:JavaLangReflectConstructor_class_()];
}

// Return a method instance described by a name and an array of
// parameter types.  If the named method isn't a member of the specified
// class, return a superclass method if available.
- (JavaLangReflectMethod *)getMethod:(NSString *)name
                      parameterTypes:(IOSObjectArray *)types {
  NSString *translatedName = IOSClass_GetTranslatedMethodName(self, name, types);
  IOSClass *cls = self;
  do {
    JavaLangReflectMethod *method = [cls findMethodWithTranslatedName:translatedName
                                                      checkSupertypes:true];
    if (method != nil) {
      if (([method getModifiers] & JavaLangReflectModifier_PUBLIC) == 0) {
        break;
      }
      return method;
    }
    for (IOSClass *p in [cls getInterfacesInternal]) {
      method = [p findMethodWithTranslatedName:translatedName checkSupertypes:true];
      if (method != nil) {
        return method;
      }
    }
  } while ((cls = [cls getSuperclass]) != nil);
  @throw AUTORELEASE([[JavaLangNoSuchMethodException alloc] initWithNSString:name]);
}

// Return a method instance described by a name and an array of parameter
// types.  Return nil if the named method is not a member of this class.
- (JavaLangReflectMethod *)getDeclaredMethod:(NSString *)name
                              parameterTypes:(IOSObjectArray *)types {
  JavaLangReflectMethod *result =
      [self findMethodWithTranslatedName:IOSClass_GetTranslatedMethodName(self, name, types)
                         checkSupertypes:false];
  if (!result) {
    @throw AUTORELEASE([[JavaLangNoSuchMethodException alloc] initWithNSString:name]);
  }
  return result;
}

- (JavaLangReflectMethod *)findMethodWithTranslatedName:(NSString *)objcName
                                        checkSupertypes:(jboolean)includePublic {
  return nil; // Overriden by subclasses.
}

- (JavaLangReflectConstructor *)findConstructorWithTranslatedName:(NSString *)objcName {
  return nil; // Overriden by subclasses.
}

static NSString *Capitalize(NSString *s) {
  if ([s length] == 0) {
    return s;
  }
  // Only capitalize the first character, as NSString.capitalizedString
  // will make all other characters lowercase.
  NSString *firstChar = [[s substringToIndex:1] capitalizedString];
  return [s stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                    withString:firstChar];
}

static NSString *GetParameterKeyword(IOSClass *paramType) {
  if (paramType == IOSClass_objectClass) {
    return @"Id";
  }
  return Capitalize([paramType objcName]);
}

static jint countArgs(char *s) {
  jint count = 0;
  while (*s) {
    if (*s++ == ':') {
      ++count;
    }
  }
  return count;
}

const J2ObjcMethodInfo *FindMethodMetadataWithJavaName(
    const J2ObjcClassInfo *metadata, NSString *javaName, jint argCount) {
  if (metadata) {
    const char *name = [javaName UTF8String];
    for (int i = 0; i < metadata->methodCount; i++) {
      const char *cname = metadata->methods[i].javaName;
      if (cname && strcmp(name, cname) == 0
          && argCount == countArgs((char *)metadata->methods[i].selector)) {
        // Skip leading matches followed by "With", which follow the standard selector
        // pattern using typed parameters. This method is for resolving mapped methods
        // which don't follow that pattern, and thus need help from metadata.
        char buffer[256];
        strcpy(buffer, cname);
        strcat(buffer, "With");
        if (strncmp(buffer, metadata->methods[i].selector, strlen(buffer)) != 0) {
          return &metadata->methods[i];
        }
      }
    }
  }
  return nil;
}


// Return a method's selector as it would be created during j2objc translation.
// The format is "name" with no parameters, "nameWithType:" for one parameter,
// and "nameWithType:withType:..." for multiple parameters.
NSString *IOSClass_GetTranslatedMethodName(IOSClass *cls, NSString *name,
                                           IOSObjectArray *parameterTypes) {
  nil_chk(name);
  IOSClass *metaCls = cls;
  jint nParameters = parameterTypes ? parameterTypes->size_ : 0;
  while (metaCls) {
    const J2ObjcMethodInfo *methodData =
        FindMethodMetadataWithJavaName(metaCls->metadata_, name, nParameters);
    if (methodData) {
      return JreMethodObjcName(methodData);
    }
    metaCls = [metaCls getSuperclass];
  }
  if (nParameters == 0) {
    return name;
  }
  IOSClass *firstParameterType = parameterTypes->buffer_[0];
  NSMutableString *translatedName = [NSMutableString stringWithCapacity:128];
  [translatedName appendFormat:@"%@With%@:", name, GetParameterKeyword(firstParameterType)];
  for (jint i = 1; i < nParameters; i++) {
    IOSClass *parameterType = parameterTypes->buffer_[i];
    [translatedName appendFormat:@"with%@:", GetParameterKeyword(parameterType)];
  }
  return translatedName;
}

- (IOSClass *)getComponentType {
  return nil;
}

- (JavaLangReflectConstructor *)getConstructor:(IOSObjectArray *)parameterTypes {
  // Java's getConstructor() only returns the constructor if it's public.
  // However, all constructors in Objective-C are public, so this method
  // is identical to getDeclaredConstructor().
  @throw AUTORELEASE([[JavaLangNoSuchMethodException alloc] init]);
}

- (JavaLangReflectConstructor *)getDeclaredConstructor:(IOSObjectArray *)parameterTypes {
  @throw AUTORELEASE([[JavaLangNoSuchMethodException alloc] init]);
}

- (jboolean)isAssignableFrom:(IOSClass *)cls {
  @throw AUTORELEASE([[JavaLangAssertionError alloc] initWithId:@"abstract method not overridden"]);
}

- (IOSClass *)asSubclass:(IOSClass *)cls {
  if ([cls isAssignableFrom:self]) {
    return self;
  }

  @throw AUTORELEASE([[JavaLangClassCastException alloc] initWithNSString:[self description]]);
}

- (NSString *)description {
  // matches java.lang.Class.toString() output
  return [NSString stringWithFormat:@"class %@", [self getName]];
}

- (NSString *)binaryName {
  NSString *name = [self getName];
  return [NSString stringWithFormat:@"L%@;", name];
}

static NSString *CamelCasePackage(NSString *package) {
  NSArray *parts = [package componentsSeparatedByString:@"."];
  NSMutableString *result = [NSMutableString string];
  for (NSString *part in parts) {
    [result appendString:Capitalize(part)];
  }
  return result;
}

static IOSClass *ClassForIosName(NSString *iosName) {
  nil_chk(iosName);
  // Some protocols have a sibling class that contains the metadata and any
  // constants that are defined. We must look for the protocol before the class
  // to ensure we create a IOSProtocolClass for such cases. NSObject must be
  // special-cased because it also has a protocol but we want to return an
  // IOSConcreteClass instance for it.
  if ([iosName isEqualToString:@"NSObject"]) {
    return IOSClass_objectClass;
  }
  Protocol *protocol = NSProtocolFromString(iosName);
  if (protocol) {
    return IOSClass_fromProtocol(protocol);
  }
  Class clazz = NSClassFromString(iosName);
  if (clazz) {
    return IOSClass_fromClass(clazz);
  }
  return nil;
}

static NSString *FindRenamedPackagePrefix(NSString *package) {
  NSString *prefix = nil;

  // Check for a package-info class that has a __prefix method.
  NSString *pkgInfoName = [CamelCasePackage(package) stringByAppendingString:@"package_info"];
  Class pkgInfoCls = NSClassFromString(pkgInfoName);
  Method prefixMethod = JreFindClassMethod(pkgInfoCls, "__prefix");
  if (prefixMethod) {
    prefix = method_invoke(pkgInfoCls, prefixMethod);
  }
  if (!prefix) {
    // Check whether package has a mapped prefix property.
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      JavaIoInputStream *prefixesResource =
          [IOSClass_objectClass getResourceAsStream:PREFIX_MAPPING_RESOURCE];
      if (prefixesResource) {
        prefixMapping = [[JavaUtilProperties alloc] init];
        [prefixMapping load__WithJavaIoInputStream:prefixesResource];
      }
    });
    prefix = [prefixMapping getPropertyWithNSString:package];
  }
  if (!prefix && prefixMapping) {
    // Check each prefix mapping to see if it's a matching wildcard.
    id<JavaUtilEnumeration> names = [prefixMapping propertyNames];
    while ([names hasMoreElements]) {
      NSString *key = (NSString *) [names nextElement];
      // Same translation as j2objc's PackagePrefixes.wildcardToRegex().
      NSString *regex;
      if ([key hasSuffix:@".*"]) {
        NSString *root = [[key substring:0 endIndex:((jint) [key length]) - 2]
                          replace:@"." withSequence:@"\\."];
        regex = [NSString stringWithFormat:@"^(%@|%@\\..*)$", root, root];
      } else {
        regex = [NSString stringWithFormat:@"^%@$",
                 [[key replace:@"." withSequence:@"\\."]replace:@"\\*" withSequence:@".*"]];
      }
      if ([package matches:regex]) {
        prefix = [prefixMapping getPropertyWithNSString:key];
        break;
      }
    }
  }
  return prefix;
}

+ (IOSClass *)classForIosName:(NSString *)iosName {
  return ClassForIosName(iosName);
}

static IOSClass *ClassForJavaName(NSString *name) {
  // First check if this is a mapped name.
  NSString *mappedName = [IOSClass_mappedClasses objectForKey:name];
  if (mappedName) {
    return ClassForIosName(mappedName);
  }
  // Then check if any outer class is a mapped name.
  NSUInteger lastDollar = name.length;
  while (true) {
    lastDollar = [name rangeOfString:@"$"
                             options:NSBackwardsSearch
                               range:NSMakeRange(0, lastDollar)].location;
    if (lastDollar == NSNotFound) {
      break;
    }
    NSString *prefix = [name substringToIndex:lastDollar];
    NSString *mappedName = [IOSClass_mappedClasses objectForKey:prefix];
    if (mappedName) {
      NSString *suffix = [name substringFromIndex:lastDollar];
      suffix = [suffix stringByReplacingOccurrencesOfString:@"$" withString:@"_"];
      return ClassForIosName([mappedName stringByAppendingString:suffix]);
    }
  }

  // Separate package from class names.
  NSUInteger lastDot = [name rangeOfString:@"." options:NSBackwardsSearch].location;
  if (lastDot == NSNotFound) {
    // Empty package.
    return ClassForIosName([name stringByReplacingOccurrencesOfString:@"$" withString:@"_"]);
  }
  NSString *package = [name substringToIndex:lastDot];
  NSString *suffix = [[name substringFromIndex:lastDot + 1]
      stringByReplacingOccurrencesOfString:@"$" withString:@"_"];
  // First check if the class can be found with the default camel case package. This avoids the
  // expensive FindRenamedPackagePrefix if possible.
  IOSClass *cls = ClassForIosName([CamelCasePackage(package) stringByAppendingString:suffix]);
  if (cls) {
    return cls;
  }
  // Check if the package has a renamed prefix.
  NSString *renamedPackage = FindRenamedPackagePrefix(package);
  if (renamedPackage) {
    return ClassForIosName([renamedPackage stringByAppendingString:suffix]);
  }
  return nil;
}

static IOSClass *IOSClass_PrimitiveClassForChar(unichar c) {
  switch (c) {
    case 'B': return IOSClass_byteClass;
    case 'C': return IOSClass_charClass;
    case 'D': return IOSClass_doubleClass;
    case 'F': return IOSClass_floatClass;
    case 'I': return IOSClass_intClass;
    case 'J': return IOSClass_longClass;
    case 'S': return IOSClass_shortClass;
    case 'Z': return IOSClass_booleanClass;
    case 'V': return IOSClass_voidClass;
    default: return nil;
  }
}

+ (IOSClass *)primitiveClassForChar:(unichar)c {
  return IOSClass_PrimitiveClassForChar(c);
}

static IOSClass *IOSClass_ArrayClassForName(NSString *name, NSUInteger index) {
  IOSClass *componentType = nil;
  unichar c = [name characterAtIndex:index];
  switch (c) {
    case 'L':
      {
        NSUInteger length = [name length];
        if ([name characterAtIndex:length - 1] == ';') {
          componentType = ClassForJavaName(
              [name substringWithRange:NSMakeRange(index + 1, length - index - 2)]);
        }
        break;
      }
    case '[':
      componentType = IOSClass_ArrayClassForName(name, index + 1);
      break;
    default:
      if ([name length] == index + 1) {
        componentType = IOSClass_PrimitiveClassForChar(c);
      }
      break;
  }
  if (componentType) {
    return IOSClass_arrayOf(componentType);
  }
  return nil;
}

IOSClass *IOSClass_forName_(NSString *className) {
  nil_chk(className);
  IOSClass *iosClass = nil;
  if ([className length] > 0) {
    if ([className characterAtIndex:0] == '[') {
      iosClass = IOSClass_ArrayClassForName(className, 1);
    } else {
      iosClass = ClassForJavaName(className);
    }
  }
  if (iosClass) {
    return iosClass;
  }
  @throw AUTORELEASE([[JavaLangClassNotFoundException alloc] initWithNSString:className]);
}

+ (IOSClass *)forName:(NSString *)className {
  return IOSClass_forName_(className);
}

IOSClass *IOSClass_forName_initialize_classLoader_(
    NSString *className, jboolean load, JavaLangClassLoader *loader) {
  return IOSClass_forName_(className);
}

+ (IOSClass *)forName:(NSString *)className
           initialize:(jboolean)load
          classLoader:(JavaLangClassLoader *)loader {
  return IOSClass_forName_initialize_classLoader_(className, load, loader);
}

- (id)cast:(id)throwable {
  // There's no need to actually cast this here, as the translator will add
  // a C cast since the return type is a type variable.
  return throwable;
}

- (IOSClass *)getEnclosingClass {
  NSString *enclosingName = JreClassEnclosingName(metadata_);
  if (!enclosingName) {
    return nil;
  }
  NSMutableString *qName = [NSMutableString string];
  NSString *packageName = JreClassPackageName(metadata_);
  if (packageName) {
    [qName appendString:packageName];
    [qName appendString:@"."];
  }
  [qName appendString:enclosingName];
  return ClassForJavaName(qName);
}

- (jboolean)isArray {
  return false;
}

- (jboolean)isEnum {
  return false;
}

- (jboolean)isInterface {
  return false;
}

- (jboolean)isPrimitive {
  return false;  // Overridden by IOSPrimitiveClass.
}

static jboolean hasModifier(IOSClass *cls, int flag) {
  return cls->metadata_ ? (cls->metadata_->modifiers & flag) > 0 : false;
}

- (jboolean)isAnnotation {
  return hasModifier(self, JavaLangReflectModifier_ANNOTATION);
}

- (jboolean)isMemberClass {
  return metadata_ && metadata_->enclosingName && ![self isAnonymousClass];
}

- (jboolean)isLocalClass {
  return [self getEnclosingMethod] && ![self isAnonymousClass];
}

- (jboolean)isSynthetic {
  return hasModifier(self, JavaLangReflectModifier_SYNTHETIC);
}

- (IOSObjectArray *)getInterfacesInternal {
  return IOSClass_emptyClassArray;
}

- (IOSObjectArray *)getInterfaces {
  return [IOSObjectArray arrayWithArray:[self getInterfacesInternal]];
}

- (IOSObjectArray *)getGenericInterfaces {
  if ([self isPrimitive]) {
    return [IOSObjectArray arrayWithLength:0 type:JavaLangReflectType_class_()];
  }
  NSString *genericSignature = JreClassGenericString(metadata_);
  if (!genericSignature) {
    // Just return regular interfaces list.
    IOSObjectArray *interfaces = [self getInterfacesInternal];
    return [IOSObjectArray arrayWithObjects:interfaces->buffer_
                                      count:interfaces->size_
                                       type:JavaLangReflectType_class_()];
  }
  LibcoreReflectGenericSignatureParser *parser =
      [[LibcoreReflectGenericSignatureParser alloc]
       initWithJavaLangClassLoader:JavaLangClassLoader_getSystemClassLoader()];
  [parser parseForClassWithJavaLangReflectGenericDeclaration:self
                                                withNSString:genericSignature];
  IOSObjectArray *result =
      [LibcoreReflectTypes getTypeArray:parser->interfaceTypes_ clone:false];
  [parser release];
  return result;
}

// Checks if a ObjC protocol is a translated Java interface.
bool IsJavaInterface(Protocol *protocol) {
  if (protocol == @protocol(NSCopying)) {
    return true;
  }
  unsigned int count;
  Protocol **protocolList = protocol_copyProtocolList(protocol, &count);
  bool result = false;
  // Every translated Java interface has JavaObject as the last inherited protocol.
  // Every translated Java annotation has JavaLangAnnotationAnnotation as its only inherited
  // protocol.
  for (unsigned int i = 0; i < count; i++) {
    if (protocolList[i] == @protocol(JavaObject)
        || protocolList[i] == @protocol(JavaLangAnnotationAnnotation)) {
      result = true;
      break;
    }
  }
  free(protocolList);
  return result;
}

IOSObjectArray *IOSClass_NewInterfacesFromProtocolList(Protocol **list, unsigned int count) {
  IOSClass *buffer[count];
  unsigned int actualCount = 0;
  for (unsigned int i = 0; i < count; i++) {
    Protocol *protocol = list[i];
    // It is not uncommon for protocols to be added to classes like NSObject using categories. Here
    // we filter out any protocols that aren't translated from Java interfaces.
    if (IsJavaInterface(protocol)) {
      buffer[actualCount++] = IOSClass_fromProtocol(list[i]);
    }
  }
  return [IOSObjectArray newArrayWithObjects:buffer
                                       count:actualCount
                                        type:IOSClass_class_()];
}

- (IOSObjectArray *)getTypeParameters {
  NSString *genericSignature = JreClassGenericString(metadata_);
  if (!genericSignature) {
    return [IOSObjectArray arrayWithLength:0 type:JavaLangReflectTypeVariable_class_()];
  }
  LibcoreReflectGenericSignatureParser *parser =
      [[LibcoreReflectGenericSignatureParser alloc]
       initWithJavaLangClassLoader:JavaLangClassLoader_getSystemClassLoader()];
  [parser parseForClassWithJavaLangReflectGenericDeclaration:self
                                                withNSString:genericSignature];
  IOSObjectArray *result = [[parser->formalTypeParameters_ retain] autorelease];
  [parser release];
  return result;
}

- (id<JavaLangAnnotationAnnotation>)getAnnotationWithIOSClass:(IOSClass *)annotationClass {
  nil_chk(annotationClass);
  IOSObjectArray *annotations = [self getAnnotations];
  jint n = annotations->size_;
  for (jint i = 0; i < n; i++) {
    id annotation = annotations->buffer_[i];
    if ([annotationClass isInstance:annotation]) {
      return annotation;
    }
  }
  return nil;
}

- (jboolean)isAnnotationPresentWithIOSClass:(IOSClass *)annotationClass {
  return [self getAnnotationWithIOSClass:annotationClass] != nil;
}

- (IOSObjectArray *)getAnnotations {
  NSMutableArray *array = [[NSMutableArray alloc] init];
  IOSObjectArray *declared = [self getDeclaredAnnotations];
  for (jint i = 0; i < declared->size_; i++) {
    [array addObject:declared->buffer_[i]];
  }

  // Check for any inherited annotations.
  IOSClass *cls = [self getSuperclass];
  IOSClass *inheritedAnnotation = JavaLangAnnotationInherited_class_();
  while (cls) {
    IOSObjectArray *declared = [cls getDeclaredAnnotations];
    for (jint i = 0; i < declared->size_; i++) {
      id<JavaLangAnnotationAnnotation> annotation = declared->buffer_[i];
      IOSObjectArray *attributes = [[annotation getClass] getDeclaredAnnotations];
      for (jint j = 0; j < attributes->size_; j++) {
        id<JavaLangAnnotationAnnotation> attribute = attributes->buffer_[j];
        if (inheritedAnnotation == [attribute annotationType]) {
          [array addObject:annotation];
        }
      }
    }
    cls = [cls getSuperclass];
  }
  IOSObjectArray *result =
      [IOSObjectArray arrayWithNSArray:array type:JavaLangAnnotationAnnotation_class_()];
  [array release];
  return result;
}

- (IOSObjectArray *)getDeclaredAnnotations {
  Class cls = self.objcClass;
  if (cls) {
    Method annotationsMethod = JreFindClassMethod(cls, "__annotations");
    if (annotationsMethod) {
      return method_invoke(cls, annotationsMethod);
    }
  }
  return [IOSObjectArray arrayWithLength:0 type:JavaLangAnnotationAnnotation_class_()];
}

- (id<JavaLangAnnotationAnnotation>)getDeclaredAnnotationWithIOSClass:(IOSClass *)annotationClass {
  return ((id<JavaLangAnnotationAnnotation>)
      LibcoreReflectAnnotatedElements_getDeclaredAnnotationWithJavaLangReflectAnnotatedElement_withIOSClass_(
          self, annotationClass));
}

- (IOSObjectArray *)getAnnotationsByTypeWithIOSClass:(IOSClass *)annotationClass {
  return LibcoreReflectAnnotatedElements_getAnnotationsByTypeWithJavaLangReflectAnnotatedElement_withIOSClass_(
      self, annotationClass);
}

- (IOSObjectArray *)getDeclaredAnnotationsByTypeWithIOSClass:(IOSClass *)annotationClass {
  return LibcoreReflectAnnotatedElements_getDeclaredAnnotationsByTypeWithJavaLangReflectAnnotatedElement_withIOSClass_(
      self, annotationClass);
}

- (const J2ObjcClassInfo *)getMetadata {
  return metadata_;
}

- (id)getPackage {
  NSString *packageName = JreClassPackageName(metadata_);
  if (packageName) {
    return AUTORELEASE([[JavaLangPackage alloc] initWithNSString:packageName
                                                    withNSString:nil
                                                    withNSString:nil
                                                    withNSString:nil
                                                    withNSString:nil
                                                    withNSString:nil
                                                    withNSString:nil
                                                  withJavaNetURL:nil
                                         withJavaLangClassLoader:nil]);
  }
  return nil;
}

- (id)getClassLoader {
  return JavaLangClassLoader_getSystemClassLoader();
}

// Adds all the fields for a specified class to a specified dictionary.
static void GetFieldsFromClass(IOSClass *iosClass, NSMutableDictionary *fields,
    jboolean publicOnly) {
  const J2ObjcClassInfo *metadata = IOSClass_GetMetadataOrFail(iosClass);
  for (int i = 0; i < metadata->fieldCount; i++) {
    const J2ObjcFieldInfo *fieldInfo = &metadata->fields[i];
    if (publicOnly && (fieldInfo->modifiers & JavaLangReflectModifier_PUBLIC) == 0) {
      continue;
    }
    Ivar ivar = class_getInstanceVariable(iosClass.objcClass, fieldInfo->name);
    JavaLangReflectField *field = [JavaLangReflectField fieldWithIvar:ivar
                                                            withClass:iosClass
                                                         withMetadata:fieldInfo];
    NSString *name = [field getName];
    if (![fields valueForKey:name]) {
      [fields setObject:field forKey:name];
    }
  };
}

JavaLangReflectField *findDeclaredField(IOSClass *iosClass, NSString *name, jboolean publicOnly) {
  const J2ObjcClassInfo *metadata = IOSClass_GetMetadataOrFail(iosClass);
  const J2ObjcFieldInfo *fieldMeta = JreFindFieldInfo(metadata, [name UTF8String]);
  if (fieldMeta && (!publicOnly || (fieldMeta->modifiers & JavaLangReflectModifier_PUBLIC) != 0)) {
    Ivar ivar = class_getInstanceVariable(iosClass.objcClass, fieldMeta->name);
    return [JavaLangReflectField fieldWithIvar:ivar
                                     withClass:iosClass
                                  withMetadata:fieldMeta];
  }
  return nil;
}

static JavaLangReflectField *findField(IOSClass *iosClass, NSString *name) {
  while (iosClass) {
    JavaLangReflectField *field = findDeclaredField(iosClass, name, true);
    if (field) {
      return field;
    }
    for (IOSClass *p in [iosClass getInterfacesInternal]) {
      JavaLangReflectField *field = findField(p, name);
      if (field) {
        return field;
      }
    }
    iosClass = [iosClass getSuperclass];
  }
  return nil;
}

- (JavaLangReflectField *)getDeclaredField:(NSString *)name {
  nil_chk(name);
  JavaLangReflectField *field = findDeclaredField(self, name, false);
  if (field) {
    return field;
  }
  @throw AUTORELEASE([[JavaLangNoSuchFieldException alloc] initWithNSString:name]);
}

- (JavaLangReflectField *)getField:(NSString *)name {
  nil_chk(name);
  JavaLangReflectField *field = findField(self, name);
  if (field) {
    return field;
  }
  @throw AUTORELEASE([[JavaLangNoSuchFieldException alloc] initWithNSString:name]);
}

IOSObjectArray *copyFieldsToObjectArray(NSArray *fields) {
  jint count = (jint)[fields count];
  IOSObjectArray *results =
      [IOSObjectArray arrayWithLength:count type:JavaLangReflectField_class_()];
  for (jint i = 0; i < count; i++) {
    [results replaceObjectAtIndex:i withObject:[fields objectAtIndex:i]];
  }
  return results;
}

- (IOSObjectArray *)getDeclaredFields {
  NSMutableDictionary *fieldDictionary = [NSMutableDictionary dictionary];
  if (metadata_) {
    GetFieldsFromClass(self, fieldDictionary, false);
  }
  return copyFieldsToObjectArray([fieldDictionary allValues]);
}

static void getAllFields(IOSClass *cls, NSMutableDictionary *fieldMap) {
  GetFieldsFromClass(cls, fieldMap, true);
  for (IOSClass *p in [cls getInterfacesInternal]) {
    getAllFields(p, fieldMap);
  }
  while ((cls = [cls getSuperclass])) {
    getAllFields(cls, fieldMap);
  }
}

- (IOSObjectArray *)getFields {
  NSMutableDictionary *fieldDictionary = [NSMutableDictionary dictionary];
  getAllFields(self, fieldDictionary);
  return copyFieldsToObjectArray([fieldDictionary allValues]);
}

static jboolean IsConstructorSelector(NSString *selector) {
  return [selector isEqualToString:@"init"] || [selector hasPrefix:@"initWith"];
}

- (JavaLangReflectMethod *)getEnclosingMethod {
  const J2ObjCEnclosingMethodInfo *metadata = JreEnclosingMethod(metadata_);
  if (metadata) {
    NSString *selector = JreEnclosingMethodSelector(metadata);
    if (IsConstructorSelector(selector)) {
      return nil;
    }
    IOSClass *type = ClassForIosName(JreEnclosingMethodTypeName(metadata));
    if (!type) {
      // Should always succeed, since the method's class should be defined in
      // the same object file as the enclosed class.
      @throw AUTORELEASE([[JavaLangAssertionError alloc] init]);
    }
    return [type findMethodWithTranslatedName:selector checkSupertypes:false];
  }
  return nil;
}

- (JavaLangReflectConstructor *)getEnclosingConstructor {
  const J2ObjCEnclosingMethodInfo *metadata = JreEnclosingMethod(metadata_);
  if (metadata) {
    NSString *selector = JreEnclosingMethodSelector(metadata);
    if (!IsConstructorSelector(selector)) {
      return nil;
    }
    IOSClass *type = ClassForIosName(JreEnclosingMethodTypeName(metadata));
    if (!type) {
      // Should always succeed, since the method's class should be defined in
      // the same object file as the enclosed class.
      @throw AUTORELEASE([[JavaLangAssertionError alloc] init]);
    }
    return [type findConstructorWithTranslatedName:selector];
  }
  return nil;
}


// Adds all the inner classes for a specified class to a specified dictionary.
static void GetInnerClasses(IOSClass *iosClass, NSMutableArray *classes,
    jboolean publicOnly, jboolean includeInterfaces) {
  const J2ObjcClassInfo *metadata = iosClass->metadata_;
  if (metadata) {
    IOSObjectArray *innerClasses = JreClassInnerClasses(metadata);
    if (!innerClasses) {
      return;
    }
    for (jint i = 0; i < innerClasses->size_; i++) {
      IOSClass *c = IOSObjectArray_Get(innerClasses, i);
      if (![c isAnonymousClass] && ![c isSynthetic]) {
        if (publicOnly && ([c getModifiers] & JavaLangReflectModifier_PUBLIC) == 0) {
          continue;
        }
        if ([c isInterface] && !includeInterfaces) {
          continue;
        }
        [classes addObject:c];
      }
    }
  }
}

- (IOSObjectArray *)getClasses {
  NSMutableArray *innerClasses = [[NSMutableArray alloc] init];
  IOSClass *cls = self;
  GetInnerClasses(cls, innerClasses, true, true);
  while ((cls = [cls getSuperclass])) {
    // Class.getClasses() shouldn't include interfaces from superclasses.
    GetInnerClasses(cls, innerClasses, true, false);
  }
  IOSObjectArray *result = [IOSObjectArray arrayWithNSArray:innerClasses
                                                       type:IOSClass_class_()];
  [innerClasses release];
  return result;
}

- (IOSObjectArray *)getDeclaredClasses {
  NSMutableArray *declaredClasses = [[NSMutableArray alloc] init];
  GetInnerClasses(self, declaredClasses, false, true);
  IOSObjectArray *result = [IOSObjectArray arrayWithNSArray:declaredClasses
                                                       type:IOSClass_class_()];
  [declaredClasses release];
  return result;
}

- (jboolean)isAnonymousClass {
  return false;
}

- (jboolean)desiredAssertionStatus {
  return false;
}

static IOSObjectArray *GetEnumConstants(IOSClass *cls) {
  return [cls isEnum] ? JavaLangEnum_getSharedConstantsWithIOSClass_(cls) : nil;
}

- (IOSObjectArray *)getEnumConstants {
  return [GetEnumConstants(self) clone];
}

// Package private method. In OpenJDK it differentiated from the above because
// a single constants array is cached and then cloned by getEnumConstants().
// That's not necessary here, since the Enum.getSharedConstants() function
// creates a new array.
- (IOSObjectArray *)getEnumConstantsShared {
  return GetEnumConstants(self);
}

- (Class)objcArrayClass {
  return [IOSObjectArray class];
}

- (size_t)getSizeof {
  return sizeof(id);
}

NSString *resolveResourceName(IOSClass *cls, NSString *resourceName) {
  if (!resourceName || [resourceName length] == 0) {
    return resourceName;
  }
  if ([resourceName characterAtIndex:0] == '/') {
    return resourceName;
  }
  NSString *relativePath = [[[cls getPackage] getName] stringByReplacingOccurrencesOfString:@"."
                                                                                 withString:@"/"];
  return [NSString stringWithFormat:@"/%@/%@", relativePath, resourceName];
}

- (JavaNetURL *)getResource:(NSString *)name {
  return [[self getClassLoader] getResourceWithNSString:resolveResourceName(self, name)];
}

- (JavaIoInputStream *)getResourceAsStream:(NSString *)name {
  return [[self getClassLoader] getResourceAsStreamWithNSString:resolveResourceName(self, name)];
}

// These java.security methods don't have an iOS equivalent, so always return nil.
- (id)getProtectionDomain {
  return nil;
}

- (id)getSigners {
  return nil;
}


- (id)__boxValue:(J2ObjcRawValue *)rawValue {
  return (id)rawValue->asId;
}

- (jboolean)__unboxValue:(id)value toRawValue:(J2ObjcRawValue *)rawValue {
  rawValue->asId = value;
  return true;
}

- (void)__readRawValue:(J2ObjcRawValue *)rawValue fromAddress:(const void *)addr {
  rawValue->asId = *(id *)addr;
}

- (void)__writeRawValue:(J2ObjcRawValue *)rawValue toAddress:(const void *)addr {
  *(id *)addr = (id)rawValue->asId;
}

- (jboolean)__convertRawValue:(J2ObjcRawValue *)rawValue toType:(IOSClass *)type {
  // No conversion necessary if both types are ids.
  return ![type isPrimitive];
}

// Implementing NSCopying allows IOSClass objects to be used as keys in the
// class cache.
- (instancetype)copyWithZone:(NSZone *)zone {
  return self;
}

- (IOSClass *)getClass {
  return IOSClass_class_();
}

static jboolean IsStringType(Class cls) {
  // We can't trigger class initialization because that might recursively enter
  // FetchClass and result in deadlock within the FastPointerLookup. Therefore,
  // we can't use [cls isSubclassOfClass:[NSString class]].
  Class stringCls = [NSString class];
  while (cls) {
    if (cls == stringCls) {
      return true;
    }
    cls = class_getSuperclass(cls);
  }
  return false;
}

static void *ClassLookup(void *clsPtr) {
  Class cls = (Class)clsPtr;
  if (cls == [NSObject class]) {
    return [[IOSMappedClass alloc] initWithClass:[NSObject class]
                                         package:@"java.lang"
                                            name:@"Object"];
  } else if (IsStringType(cls)) {
    // NSString is implemented by several subclasses.
    // Thread safety is guaranteed by the FastPointerLookup that calls this.
    static IOSClass *stringClass;
    if (!stringClass) {
      stringClass = [[IOSMappedClass alloc] initWithClass:[NSString class]
                                                  package:@"java.lang"
                                                     name:@"String"];
    }
    return stringClass;
  } else {
    IOSClass *result = [[IOSConcreteClass alloc] initWithClass:cls];
    return result;
  }
  return NULL;
}

static FastPointerLookup_t classLookup = FAST_POINTER_LOOKUP_INIT(&ClassLookup);

IOSClass *IOSClass_fromClass(Class cls) {
  // We get deadlock if IOSClass is not initialized before entering the fast
  // lookup because +initialize makes calls into IOSClass_fromClass().
  IOSClass_initialize();
  return (IOSClass *)FastPointerLookup(&classLookup, cls);
}

IOSClass *IOSClass_NewProxyClass(Class cls) {
  IOSClass *result = [[IOSProxyClass alloc] initWithClass:cls];
  if (!FastPointerLookupAddMapping(&classLookup, cls, result)) {
    // This function should only be called by java.lang.reflect.Proxy
    // immediately after creating a new proxy class.
    @throw AUTORELEASE([[JavaLangAssertionError alloc] init]);
  }
  return result;
}

static void *ProtocolLookup(void *protocol) {
  return [[IOSProtocolClass alloc] initWithProtocol:(Protocol *)protocol];
}

static FastPointerLookup_t protocolLookup = FAST_POINTER_LOOKUP_INIT(&ProtocolLookup);

IOSClass *IOSClass_fromProtocol(Protocol *protocol) {
  return (IOSClass *)FastPointerLookup(&protocolLookup, protocol);
}

static void *ArrayLookup(void *componentType) {
  return [[IOSArrayClass alloc] initWithComponentType:(IOSClass *)componentType];
}

static FastPointerLookup_t arrayLookup = FAST_POINTER_LOOKUP_INIT(&ArrayLookup);

IOSClass *IOSClass_arrayOf(IOSClass *componentType) {
  return (IOSClass *)FastPointerLookup(&arrayLookup, componentType);
}

IOSClass *IOSClass_arrayType(IOSClass *componentType, jint dimensions) {
  IOSClass *result = (IOSClass *)FastPointerLookup(&arrayLookup, componentType);
  while (--dimensions > 0) {
    result = (IOSClass *)FastPointerLookup(&arrayLookup, result);
  }
  return result;
}

+ (void)initialize {
  if (self == [IOSClass class]) {
    // Explicitly mapped classes are defined in Types.initializeTypeMap().
    // If types are added to that method (it's rare) they need to be added here.
    IOSClass_mappedClasses = [[NSDictionary alloc] initWithObjectsAndKeys:
         @"NSObject",    @"java.lang.Object",
         @"IOSClass",    @"java.lang.Class",
         @"NSNumber",    @"java.lang.Number",
         @"NSString",    @"java.lang.String",
         @"NSException", @"java.lang.Throwable",
         @"NSCopying",   @"java.lang.Cloneable", nil];

    IOSClass_byteClass = [[IOSPrimitiveClass alloc] initWithName:@"byte" type:@"B"];
    IOSClass_charClass = [[IOSPrimitiveClass alloc] initWithName:@"char" type:@"C"];
    IOSClass_doubleClass = [[IOSPrimitiveClass alloc] initWithName:@"double" type:@"D"];
    IOSClass_floatClass = [[IOSPrimitiveClass alloc] initWithName:@"float" type:@"F"];
    IOSClass_intClass = [[IOSPrimitiveClass alloc] initWithName:@"int" type:@"I"];
    IOSClass_longClass = [[IOSPrimitiveClass alloc] initWithName:@"long" type:@"J"];
    IOSClass_shortClass = [[IOSPrimitiveClass alloc] initWithName:@"short" type:@"S"];
    IOSClass_booleanClass = [[IOSPrimitiveClass alloc] initWithName:@"boolean" type:@"Z"];
    IOSClass_voidClass = [[IOSPrimitiveClass alloc] initWithName:@"void" type:@"V"];

    IOSClass_objectClass = IOSClass_fromClass([NSObject class]);

    IOSClass_emptyClassArray = [IOSObjectArray newArrayWithLength:0 type:IOSClass_class_()];

    // Load and initialize JRE categories, using their dummy classes.
    [JreObjectCategoryDummy class];
    [JreStringCategoryDummy class];
    [JreNumberCategoryDummy class];
    [JreThrowableCategoryDummy class];
    [NSCopying class];

    // Verify that these categories successfully loaded.
    if ([[NSObject class] instanceMethodSignatureForSelector:@selector(compareToWithId:)] == NULL ||
        [[NSString class] instanceMethodSignatureForSelector:@selector(trim)] == NULL ||
        ![NSNumber conformsToProtocol:@protocol(JavaIoSerializable)]) {
      [NSException raise:@"J2ObjCLinkError"
                  format:@"Your project is not configured to load categories from the JRE "
                          "emulation library. Try adding the -force_load linker flag."];
    }

    J2OBJC_SET_INITIALIZED(IOSClass)
  }
}

+ (void)load {
  // Initialize ICU function pointers.
  J2ObjC_icu_init();
}

// Generated by running the translator over the java.lang.Class stub file.
+ (const J2ObjcClassInfo *)__metadata {
  static const J2ObjcMethodInfo methods[] = {
    { "forName:", "forName", "Ljava.lang.Class;", 0x9, "Ljava.lang.ClassNotFoundException;",
      "(Ljava/lang/String;)Ljava/lang/Class<*>;" },
    { "forName:initialize:classLoader:", "forName", "Ljava.lang.Class;", 0x9,
      "Ljava.lang.ClassNotFoundException;",
      "(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class<*>;" },
    { "asSubclass:", "asSubclass", "Ljava.lang.Class;", 0x1, NULL,
      "<U:Ljava/lang/Object;>(Ljava/lang/Class<TU;>;)Ljava/lang/Class<+TU;>;" },
    { "cast:", "cast", "TT;", 0x1, NULL, "(Ljava/lang/Object;)TT;" },
    { "desiredAssertionStatus", NULL, "Z", 0x1, NULL, NULL },
    { "getAnnotationWithIOSClass:", "getAnnotation", "TA;", 0x1, NULL,
      "<A::Ljava/lang/annotation/Annotation;>(Ljava/lang/Class<TA;>;)TA;" },
    { "getAnnotations", NULL, "[Ljava.lang.annotation.Annotation;", 0x1, NULL, NULL },
    { "getCanonicalName", NULL, "Ljava.lang.String;", 0x1, NULL, NULL },
    { "getClasses", NULL, "[Ljava.lang.Class;", 0x1, NULL, NULL },
    { "getClassLoader", NULL, "Ljava.lang.ClassLoader;", 0x1, NULL, NULL },
    { "getComponentType", NULL, "Ljava.lang.Class;", 0x1, NULL, "()Ljava/lang/Class<*>;" },
    { "getConstructor:", "getConstructor", "Ljava.lang.reflect.Constructor;", 0x81,
      "Ljava.lang.NoSuchMethodException;Ljava.lang.SecurityException;",
      "([Ljava/lang/Class<*>;)Ljava/lang/reflect/Constructor<TT;>;" },
    { "getConstructors", NULL, "[Ljava.lang.reflect.Constructor;", 0x1,
      "Ljava.lang.SecurityException;", NULL },
    { "getDeclaredAnnotations", NULL, "[Ljava.lang.annotation.Annotation;", 0x1, NULL, NULL },
    { "getDeclaredClasses", NULL, "[Ljava.lang.Class;", 0x1, "Ljava.lang.SecurityException;", NULL
    },
    { "getDeclaredConstructor:", "getDeclaredConstructor", "Ljava.lang.reflect.Constructor;", 0x81,
      "Ljava.lang.NoSuchMethodException;Ljava.lang.SecurityException;",
      "([Ljava/lang/Class<*>;)Ljava/lang/reflect/Constructor<TT;>;" },
    { "getDeclaredConstructors", NULL, "[Ljava.lang.reflect.Constructor;", 0x1,
      "Ljava.lang.SecurityException;", NULL },
    { "getDeclaredField:", "getDeclaredField", "Ljava.lang.reflect.Field;", 0x1,
      "Ljava.lang.NoSuchFieldException;Ljava.lang.SecurityException;", NULL },
    { "getDeclaredFields", NULL, "[Ljava.lang.reflect.Field;", 0x1, "Ljava.lang.SecurityException;",
      NULL },
    { "getDeclaredMethod:parameterTypes:", "getDeclaredMethod", "Ljava.lang.reflect.Method;", 0x81,
      "Ljava.lang.NoSuchMethodException;Ljava.lang.SecurityException;", NULL },
    { "getDeclaredMethods", NULL, "[Ljava.lang.reflect.Method;", 0x1,
      "Ljava.lang.SecurityException;", NULL },
    { "getDeclaringClass", NULL, "Ljava.lang.Class;", 0x1, NULL, "()Ljava/lang/Class<*>;" },
    { "getEnclosingClass", NULL, "Ljava.lang.Class;", 0x1, NULL, "()Ljava/lang/Class<*>;" },
    { "getEnclosingConstructor", NULL, "Ljava.lang.reflect.Constructor;", 0x1, NULL,
      "()Ljava/lang/reflect/Constructor<*>;" },
    { "getEnclosingMethod", NULL, "Ljava.lang.reflect.Method;", 0x1, NULL, NULL },
    { "getEnumConstants", NULL, "[Ljava.lang.Object;", 0x1, NULL, NULL },
    { "getEnumConstantsShared", NULL, "[Ljava.lang.Object;", 0x0, NULL, NULL },
    { "getField:", "getField", "Ljava.lang.reflect.Field;", 0x1,
      "Ljava.lang.NoSuchFieldException;Ljava.lang.SecurityException;", NULL },
    { "getFields", NULL, "[Ljava.lang.reflect.Field;", 0x1, "Ljava.lang.SecurityException;", NULL
    },
    { "getGenericInterfaces", NULL, "[Ljava.lang.reflect.Type;", 0x1, NULL, NULL },
    { "getGenericSuperclass", NULL, "Ljava.lang.reflect.Type;", 0x1, NULL, NULL },
    { "getInterfaces", NULL, "[Ljava.lang.Class;", 0x1, NULL, NULL },
    { "getMethod:parameterTypes:", "getMethod", "Ljava.lang.reflect.Method;", 0x81,
      "Ljava.lang.NoSuchMethodException;Ljava.lang.SecurityException;", NULL },
    { "getMethods", NULL, "[Ljava.lang.reflect.Method;", 0x1, "Ljava.lang.SecurityException;", NULL
    },
    { "getModifiers", NULL, "I", 0x1, NULL, NULL },
    { "getName", NULL, "Ljava.lang.String;", 0x1, NULL, NULL },
    { "getPackage", NULL, "Ljava.lang.Package;", 0x1, NULL, NULL },
    { "getProtectionDomain", NULL, "Ljava.security.ProtectionDomain;", 0x1, NULL, NULL },
    { "getResource:", "getResource", "Ljava.net.URL;", 0x1, NULL, NULL },
    { "getResourceAsStream:", "getResourceAsStream", "Ljava.io.InputStream;", 0x1, NULL, NULL },
    { "getSigners", NULL, "[Ljava.lang.Object;", 0x1, NULL, NULL },
    { "getSimpleName", NULL, "Ljava.lang.String;", 0x1, NULL, NULL },
    { "getSuperclass", NULL, "Ljava.lang.Class;", 0x1, NULL, "()Ljava/lang/Class<-TT;>;" },
    { "getTypeParameters", NULL, "[Ljava.lang.reflect.TypeVariable;", 0x1, NULL, NULL },
    { "isAnnotation", NULL, "Z", 0x1, NULL, NULL },
    { "isAnnotationPresentWithIOSClass:", "isAnnotationPresent", "Z", 0x1, NULL,
      "(Ljava/lang/Class<+Ljava/lang/annotation/Annotation;>;)Z" },
    { "isAnonymousClass", NULL, "Z", 0x1, NULL, NULL },
    { "isArray", NULL, "Z", 0x1, NULL, NULL },
    { "isAssignableFrom:", "isAssignableFrom", "Z", 0x1, NULL, "(Ljava/lang/Class<*>;)Z" },
    { "isEnum", NULL, "Z", 0x1, NULL, NULL },
    { "isInstance:", "isInstance", "Z", 0x1, NULL, NULL },
    { "isInterface", NULL, "Z", 0x1, NULL, NULL },
    { "isLocalClass", NULL, "Z", 0x1, NULL, NULL },
    { "isMemberClass", NULL, "Z", 0x1, NULL, NULL },
    { "isPrimitive", NULL, "Z", 0x1, NULL, NULL },
    { "isSynthetic", NULL, "Z", 0x1, NULL, NULL },
    { "newInstance", NULL, "TT;", 0x1,
      "Ljava.lang.InstantiationException;Ljava.lang.IllegalAccessException;", "()TT;" },
    { "description", "toString", "Ljava.lang.String;", 0x1, NULL, NULL },
    { "getDeclaredAnnotationsByTypeWithIOSClass:", "getDeclaredAnnotationsByType",
      "[Ljava.lang.annotation.Annotation;", 0x1, NULL,
      "<T::Ljava/lang/annotation/Annotation;>(Ljava/lang/Class<TT;>;)[TT;" },
    { "getAnnotationsByTypeWithIOSClass:", "getAnnotationsByType",
      "[Ljava.lang.annotation.Annotation;", 0x1, NULL,
      "<T::Ljava/lang/annotation/Annotation;>(Ljava/lang/Class<TT;>;)[TT;" },
    { "getDeclaredAnnotationWithIOSClass:", "getDeclaredAnnotation", "TT;", 0x1, NULL,
      "<T::Ljava/lang/annotation/Annotation;>(Ljava/lang/Class<TT;>;)TT;" },
    { "getAccessFlags", NULL, "I", 0x1, NULL, NULL },
    { "init", "Class", NULL, 0x1, NULL, NULL },
  };
  static const J2ObjcFieldInfo fields[] = {
    { "serialVersionUID", NULL, 0x1a, "J", NULL, NULL,
      .constantValue.asLong = IOSClass_serialVersionUID },
  };
  static const J2ObjcClassInfo _IOSClass = {
    2, "Class", "java.lang", NULL, 0x11, 63, methods, 1, fields, 0, NULL, 0, NULL, NULL,
    "<T:Ljava/lang/Object;>Ljava/lang/Object;Ljava/lang/reflect/AnnotatedElement;"
    "Ljava/lang/reflect/GenericDeclaration;Ljava/io/Serializable;Ljava/lang/reflect/Type;" };
  return &_IOSClass;
}

@end

J2OBJC_CLASS_TYPE_LITERAL_SOURCE(IOSClass)
