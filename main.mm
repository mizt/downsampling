#import <Cocoa/Cocoa.h>
#import <simd/simd.h>
#import <vector>

typedef struct _DownsamplingPlugin {
	NSString *path;
	NSString *args;
} DownsamplingPlugin;

typedef void (*DOWNSAMPLING)(std::vector<simd::float3> *, std::vector<simd::uint3> *, NSString *);

namespace TypeCheck {
	bool isSameClassName(id a, NSString *b) { return (a&&[NSStringFromClass([a class]) compare:b]==NSOrderedSame); }
	bool isString(id a) { return isSameClassName(a,@"NSTaggedPointerString")||isSameClassName(a,@"__NSCFString"); }
	bool isDictionary(id a) { return isSameClassName(a,@"__NSDictionaryM"); }
}

int main(int argc, char *argv[]) {
	@autoreleasepool {
		
		NSString *data = [NSString stringWithContentsOfFile:@"src.obj" encoding:NSUTF8StringEncoding error:nil];
		if(data) {
	
			std::vector<simd::float3> v;
			std::vector<simd::uint3> f;
			
			NSCharacterSet *WHITESPACE = [NSCharacterSet whitespaceCharacterSet];
			NSArray *lines = [data componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];
					
			for(int k=0; k<lines.count; k++) {
				NSArray *arr = [lines[k] componentsSeparatedByCharactersInSet:WHITESPACE];
				if([arr count]>0) {
					if([arr[0] isEqualToString:@"v"]) {
						if([arr count]>=4) {
							v.push_back(simd::float3{
								[arr[1] floatValue],
								[arr[2] floatValue],
								[arr[3] floatValue]
							});
						}
					}
					else if([arr[0] isEqualToString:@"f"]) {
						if([arr count]==4) {
							NSArray *a = [arr[1] componentsSeparatedByString:@"/"];
							NSArray *b = [arr[2] componentsSeparatedByString:@"/"];
							NSArray *c = [arr[3] componentsSeparatedByString:@"/"];
							f.push_back(simd::uint3{
								(unsigned int)[a[0] intValue]-1,
								(unsigned int)[b[0] intValue]-1,
								(unsigned int)[c[0] intValue]-1
							});
						}
					}
				}
			}
			
			std::vector<DownsamplingPlugin> downsamplingPlugin;
			
			NSString *jsonc = [NSString stringWithContentsOfFile:@"./settings.jsonc" encoding:NSUTF8StringEncoding error:nil];
			NSMutableDictionary *settings = [[NSMutableDictionary alloc] init];
			if(jsonc&&jsonc.length>0) {
				settings = [NSJSONSerialization JSONObjectWithData:[[[NSRegularExpression regularExpressionWithPattern:@"(/\\*[\\s\\S]*?\\*/|//.*)" options:1 error:nil] stringByReplacingMatchesInString:jsonc options:0 range:NSMakeRange(0,jsonc.length) withTemplate:@""] dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:nil];
				
				if(settings[@"Downsampling"]) {
					NSArray *Downsampling = settings[@"Downsampling"];
					for(int n=0; n<Downsampling.count; n++) {
						NSArray *arr = Downsampling[n];
						if(arr.count==2) {
							if(TypeCheck::isString(arr[0])&&TypeCheck::isDictionary(arr[1])) {
								NSData *data = [NSJSONSerialization dataWithJSONObject:arr[1] options:NSJSONReadingMutableContainers error:nil];
								downsamplingPlugin.push_back({
									.path = arr[0],
									.args = [[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]
								});
							}
						}
					}
				}
			}
			
			NSLog(@"%ld",v.size());
			
			if(downsamplingPlugin.size()>0) {
				for(int pass=0; pass<downsamplingPlugin.size(); pass++) {
					CFStringRef pluginFunctionName = (__bridge CFStringRef)([[downsamplingPlugin[pass].path lastPathComponent] stringByDeletingPathExtension]);
					CFBundleRef bundle = CFBundleCreate(kCFAllocatorDefault,(CFURLRef)[NSURL fileURLWithPath:downsamplingPlugin[pass].path]);
					if(bundle) {
						DOWNSAMPLING filter = (DOWNSAMPLING)CFBundleGetFunctionPointerForName(bundle,pluginFunctionName);
						if(filter) {
							filter(&v,&f,downsamplingPlugin[pass].args);
							if(bundle) {
								filter = nullptr;
								CFBundleUnloadExecutable(bundle);
								CFRelease(bundle);
							}
							NSLog(@"-> %ld",v.size());
						}
						downsamplingPlugin[pass].path = nil;
						downsamplingPlugin[pass].args = nil;
						bundle = nil;
					}
				}
								
				downsamplingPlugin.clear();
				downsamplingPlugin.shrink_to_fit();
				
				NSMutableString *obj = [NSMutableString stringWithString:@""];
				
				for(int n=0; n<v.size(); n++) {
					[obj appendString:[NSString stringWithFormat:@"v %0.4f %0.4f %0.4f\n",v[n].x,v[n].y,v[n].z]];
				}
				
				for(int n=0; n<f.size(); n++) {
					[obj appendString:[NSString stringWithFormat:@"f %d %d %d\n",1+f[n].x,1+f[n].y,1+f[n].z]];
				}
				
				[obj writeToFile:@"./dst.obj" atomically:YES encoding:NSUTF8StringEncoding error:nil];
				
				f.clear();
				f.shrink_to_fit();
				
				v.clear();
				v.shrink_to_fit();
			}
		}
	}
}