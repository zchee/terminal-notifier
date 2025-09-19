#import "AppDelegate.h"
#import <UserNotifications/UserNotifications.h>

static NSString * const kTerminalNotifierDefaultSender = @"com.apple.Terminal";

@interface AppDelegate () <UNUserNotificationCenterDelegate>
@property (atomic) BOOL handledResponse;
@end

@implementation NSUserDefaults (TerminalNotifierSubscript)
- (id)objectForKeyedSubscript:(id)key
{
  id obj = [self objectForKey:key];
  if ([obj isKindOfClass:[NSString class]] && [(NSString *)obj hasPrefix:@"\\"]) {
    return [(NSString *)obj substringFromIndex:1];
  }
  return obj;
}
@end

@implementation AppDelegate

+ (void)initializeUserDefaults
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSDictionary *appDefaults = @{ @"sender": kTerminalNotifierDefaultSender };
  [defaults registerDefaults:appDefaults];
}

- (void)printHelpBanner
{
  const char *appName = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"] UTF8String];
  const char *appVersion = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] UTF8String];
  printf("%s (%s) is a command-line tool to send macOS User Notifications.\n"
         "\n"
         "Usage: %s -[message|list|remove] [VALUE|ID|ID] [options]\n"
         "\n"
         "   Either of these is required (unless message data is piped to the tool):\n"
         "\n"
         "       -help              Display this help banner.\n"
         "       -version           Display terminal-notifier version.\n"
         "       -message VALUE     The notification message.\n"
         "       -remove ID         Removes a notification with the specified ‘group’ ID.\n"
         "       -list ID           If the specified ‘group’ ID exists show when it was delivered,\n"
         "                          or use ‘ALL’ as ID to see all notifications.\n"
         "                          The output is a tab-separated list.\n"
         "\n"
         "   Optional:\n"
         "\n"
         "       -title VALUE       The notification title. Defaults to ‘Terminal’.\n"
         "       -subtitle VALUE    The notification subtitle.\n"
         "       -sound NAME        The name of a sound to play when the notification appears.\n"
         "       -group ID          A string which identifies the group the notifications belong to.\n"
         "                          Old notifications with the same ID will be removed.\n"
         "       -activate ID       The bundle identifier of the application to activate when the user clicks the notification.\n"
         "       -sender ID         The bundle identifier of the application that should be shown as the sender.\n"
         "       -appIcon URL       (Deprecated) Replaced by -contentImage on modern macOS releases.\n"
         "       -contentImage URL  The URL of an image to attach to the notification.\n"
         "       -open URL          The URL of a resource to open when the user clicks the notification.\n"
         "       -execute COMMAND   A shell command to perform when the user clicks the notification.\n"
         "       -ignoreDnD         Request time-sensitive delivery (Focus).\n"
         "\n"
         "When the user activates a notification, the results are logged to the system logs.\n"
         "Use Console.app to view these logs.\n"
         "\n"
         "For more information see https://github.com/julienXX/terminal-notifier.\n",
         appName, appVersion, appName);
}

- (void)printVersion
{
  const char *appName = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"] UTF8String];
  const char *appVersion = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] UTF8String];
  printf("%s %s.\n", appName, appVersion);
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  (void)notification;

  [[self class] initializeUserDefaults];

  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  center.delegate = self;

  NSArray<NSString *> *arguments = [[NSProcessInfo processInfo] arguments];
  if ([arguments containsObject:@"-help"]) {
    [self printHelpBanner];
    exit(0);
  }

  if ([arguments containsObject:@"-version"]) {
    [self printVersion];
    exit(0);
  }

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *subtitle = defaults[@"subtitle"];
  NSString *message = defaults[@"message"];
  NSString *remove = defaults[@"remove"];
  NSString *list = defaults[@"list"];
  NSString *sound = defaults[@"sound"];

  if (message == nil && !isatty(STDIN_FILENO)) {
    NSData *inputData = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
    if (inputData.length > 0) {
      message = [[NSString alloc] initWithData:inputData encoding:NSUTF8StringEncoding];
    }
  }

  if (message == nil && remove == nil && list == nil) {
    [self deferHelpUntilPendingResponse];
    return;
  }

  if (![self ensureAuthorization]) {
    exit(1);
  }

  if (list) {
    [self listNotificationWithGroupID:list];
    return;
  }

  NSMutableDictionary *options = [NSMutableDictionary dictionary];
  [self populateOptions:options withDefaults:defaults arguments:arguments];

  if (remove) {
    [self removeNotificationWithGroupID:remove logRemovals:YES];
    if (message == nil || message.length == 0) {
      exit(0);
    }
  }

  if (message) {
    NSString *title = defaults[@"title"] ?: @"Terminal";
    [self deliverNotificationWithTitle:title
                              subtitle:subtitle
                               message:message
                               options:options
                                 sound:sound];
  }
}

#pragma mark - Authorization

- (BOOL)ensureAuthorization
{
  __block BOOL authorized = NO;
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
    switch (settings.authorizationStatus) {
      case UNAuthorizationStatusAuthorized:
      case UNAuthorizationStatusProvisional:
        authorized = YES;
        dispatch_semaphore_signal(semaphore);
        break;
      case UNAuthorizationStatusDenied:
        authorized = NO;
        dispatch_semaphore_signal(semaphore);
        break;
      case UNAuthorizationStatusNotDetermined: {
        UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionSound;
        [center requestAuthorizationWithOptions:options
                               completionHandler:^(BOOL granted, NSError *error) {
          if (!granted && error) {
            NSLog(@"Authorization failed: %@", error.localizedDescription);
          }
          authorized = granted;
          dispatch_semaphore_signal(semaphore);
        }];
        break;
      }
      default:
        authorized = NO;
        dispatch_semaphore_signal(semaphore);
        break;
    }
  }];

  dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

  if (!authorized) {
    NSLog(@"[!] Notification authorization not granted for user %@.", NSUserName());
  }

  return authorized;
}

#pragma mark - Option handling

- (void)populateOptions:(NSMutableDictionary *)options withDefaults:(NSUserDefaults *)defaults arguments:(NSArray<NSString *> *)arguments
{
  NSString *activate = defaults[@"activate"];
  if (activate.length > 0) {
    options[@"bundleID"] = activate;
  }

  NSString *group = defaults[@"group"];
  if (group.length > 0) {
    options[@"groupID"] = group;
  }

  NSString *command = defaults[@"execute"];
  if (command.length > 0) {
    options[@"command"] = command;
  }

  NSString *open = defaults[@"open"];
  if (open.length > 0) {
    NSURL *candidateURL = [NSURL URLWithString:open];
    if ((candidateURL && candidateURL.scheme.length > 0 && candidateURL.host.length > 0) || candidateURL.fileURL) {
      options[@"open"] = open;
    } else {
      NSLog(@"'%@' is not a valid URI.", open);
      exit(1);
    }
  }

  NSString *contentImage = defaults[@"contentImage"];
  if (contentImage.length > 0) {
    options[@"contentImage"] = contentImage;
  }

  NSString *appIcon = defaults[@"appIcon"];
  if (appIcon.length > 0) {
    NSLog(@"-appIcon is no longer supported on macOS Sonoma and later; using attachment instead.");
    options[@"appIcon"] = appIcon;
  }

  if ([arguments containsObject:@"-ignoreDnD"]) {
    options[@"ignoreDnD"] = @YES;
  }

  NSString *sender = defaults[@"sender"];
  NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
  if (sender.length > 0 && ![sender isEqualToString:bundleIdentifier]) {
    NSLog(@"Custom senders require code-signing with the desired bundle ID; ignoring '%@'.", sender);
  }
}

#pragma mark - Notification actions

- (void)deliverNotificationWithTitle:(NSString *)title
                             subtitle:(NSString *)subtitle
                              message:(NSString *)message
                              options:(NSDictionary *)options
                                sound:(NSString *)sound
{
  NSMutableDictionary *mutableOptions = [options mutableCopy];
  NSString *groupID = mutableOptions[@"groupID"];
  if (groupID.length > 0) {
    [self removeNotificationWithGroupID:groupID logRemovals:YES];
  }

  UNMutableNotificationContent *content = [UNMutableNotificationContent new];
  content.title = title ?: @"Terminal";
  if (subtitle.length > 0) {
    content.subtitle = subtitle;
  }
  content.body = message ?: @"";

  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  for (NSString *key in @[@"bundleID", @"groupID", @"command", @"open"]) {
    id value = mutableOptions[key];
    if (value) {
      userInfo[key] = value;
    }
  }
  content.userInfo = userInfo;

  if (groupID.length > 0) {
    content.threadIdentifier = groupID;
  }

  if (sound.length > 0) {
    if ([sound isEqualToString:@"default"]) {
      content.sound = [UNNotificationSound defaultSound];
    } else {
      content.sound = [UNNotificationSound soundNamed:(UNNotificationSoundName)sound];
    }
  }

  if ([mutableOptions[@"ignoreDnD"] boolValue]) {
    if (@available(macOS 12.0, *)) {
      content.interruptionLevel = UNNotificationInterruptionLevelTimeSensitive;
    } else {
      NSLog(@"-ignoreDnD requires macOS 12 or newer; option ignored.");
    }
  }

  NSArray<UNNotificationAttachment *> *attachments = [self attachmentsForOptions:mutableOptions];
  if (attachments.count > 0) {
    content.attachments = attachments;
  }

  NSString *identifier = groupID.length > 0 ? groupID : [[NSUUID UUID] UUIDString];
  UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier
                                                                          content:content
                                                                          trigger:nil];

  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  __block NSError *addError = nil;
  [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request
                                                            withCompletionHandler:^(NSError *error) {
    addError = error;
    dispatch_semaphore_signal(semaphore);
  }];

  dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

  if (addError) {
    NSLog(@"Failed to schedule notification: %@", addError.localizedDescription);
    exit(1);
  }

  exit(0);
}

- (NSArray<UNNotificationAttachment *> *)attachmentsForOptions:(NSDictionary *)options
{
  NSMutableArray<UNNotificationAttachment *> *attachments = [NSMutableArray array];

  NSString *contentImage = options[@"contentImage"];
  if (contentImage.length > 0) {
    UNNotificationAttachment *attachment = [self attachmentWithIdentifier:@"contentImage" urlString:contentImage];
    if (attachment) {
      [attachments addObject:attachment];
    }
  }

  NSString *appIcon = options[@"appIcon"];
  if (appIcon.length > 0) {
    UNNotificationAttachment *attachment = [self attachmentWithIdentifier:@"appIcon" urlString:appIcon];
    if (attachment) {
      [attachments addObject:attachment];
    }
  }

  return attachments;
}

- (UNNotificationAttachment *)attachmentWithIdentifier:(NSString *)identifier urlString:(NSString *)urlString
{
  NSURL *url = [NSURL URLWithString:urlString];
  if (url.scheme.length == 0) {
    url = [NSURL fileURLWithPath:urlString];
  }

  NSURL *fileURL = url;
  NSError *error = nil;

  if (!fileURL.fileURL) {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
    if (!data) {
      NSLog(@"Unable to download attachment %@: %@", urlString, error.localizedDescription);
      return nil;
    }

    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *extension = url.pathExtension.length > 0 ? url.pathExtension : @"tmp";
    NSString *filename = [[NSUUID UUID] UUIDString];
    NSURL *temporaryURL = [NSURL fileURLWithPath:[temporaryDirectory stringByAppendingPathComponent:[filename stringByAppendingPathExtension:extension]]];
    if (![data writeToURL:temporaryURL options:NSDataWritingAtomic error:&error]) {
      NSLog(@"Unable to persist attachment %@: %@", urlString, error.localizedDescription);
      return nil;
    }
    fileURL = temporaryURL;
  }

  UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:identifier
                                                                                        URL:fileURL
                                                                                    options:nil
                                                                                      error:&error];
  if (!attachment && error) {
    NSLog(@"Unable to attach image %@: %@", urlString, error.localizedDescription);
  }

  return attachment;
}

- (void)listNotificationWithGroupID:(NSString *)listGroupID
{
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  __block NSArray<UNNotification *> *deliveredNotifications = @[];

  [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
    deliveredNotifications = notifications;
    dispatch_semaphore_signal(semaphore);
  }];

  dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  for (UNNotification *notification in deliveredNotifications) {
    NSDictionary *userInfo = notification.request.content.userInfo;
    NSString *deliveredGroupID = userInfo[@"groupID"] ?: notification.request.identifier;
    NSString *title = notification.request.content.title ?: @"";
    NSString *subtitle = notification.request.content.subtitle ?: @"";
    NSString *body = notification.request.content.body ?: @"";
    NSString *deliveredAt = [[notification date] description];

    if ([listGroupID isEqualToString:@"ALL"] || [deliveredGroupID isEqualToString:listGroupID]) {
      [lines addObject:[NSString stringWithFormat:@"%@\t%@\t%@\t%@\t%@",
                        deliveredGroupID ?: @"",
                        title,
                        subtitle,
                        body,
                        deliveredAt]];
    }
  }

  if (lines.count > 0) {
    printf("GroupID\tTitle\tSubtitle\tMessage\tDelivered At\n");
    for (NSString *line in lines) {
      printf("%s\n", [line UTF8String]);
    }
  }

  exit(0);
}

- (BOOL)removeNotificationWithGroupID:(NSString *)groupID logRemovals:(BOOL)logRemovals
{
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  __block NSArray<UNNotification *> *deliveredNotifications = @[];

  [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
    deliveredNotifications = notifications;
    dispatch_semaphore_signal(semaphore);
  }];

  dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

  BOOL removed = NO;
  NSMutableArray<NSString *> *identifiers = [NSMutableArray array];

  if ([groupID isEqualToString:@"ALL"]) {
    removed = deliveredNotifications.count > 0;
    if (removed && logRemovals) {
      for (UNNotification *notification in deliveredNotifications) {
        NSString *deliveredAt = [[notification date] description];
        printf("* Removing previously sent notification, which was sent on: %s\n", [deliveredAt UTF8String]);
      }
    }
    [[UNUserNotificationCenter currentNotificationCenter] removeAllDeliveredNotifications];
    return removed;
  }

  for (UNNotification *notification in deliveredNotifications) {
    NSDictionary *userInfo = notification.request.content.userInfo;
    NSString *deliveredGroupID = userInfo[@"groupID"] ?: notification.request.identifier;
    if ([deliveredGroupID isEqualToString:groupID]) {
      [identifiers addObject:notification.request.identifier];
      if (logRemovals) {
        NSString *deliveredAt = [[notification date] description];
        printf("* Removing previously sent notification, which was sent on: %s\n", [deliveredAt UTF8String]);
      }
    }
  }

  if (identifiers.count > 0) {
    removed = YES;
    [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:identifiers];
  }

  return removed;
}

#pragma mark - UNUserNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
{
  (void)center;
  (void)notification;
  completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
 didReceiveNotificationResponse:(UNNotificationResponse *)response
          withCompletionHandler:(void (^)(void))completionHandler
{
  (void)center;

  self.handledResponse = YES;

  UNNotification *notification = response.notification;
  NSDictionary *userInfo = notification.request.content.userInfo;

  NSString *groupID = userInfo[@"groupID"];
  NSString *bundleID = userInfo[@"bundleID"];
  NSString *command = userInfo[@"command"];
  NSString *open = userInfo[@"open"];

  NSLog(@"User activated notification:");
  NSLog(@" group ID: %@", groupID);
  NSLog(@"    title: %@", notification.request.content.title);
  NSLog(@" subtitle: %@", notification.request.content.subtitle);
  NSLog(@"  message: %@", notification.request.content.body);
  NSLog(@"bundle ID: %@", bundleID);
  NSLog(@"  command: %@", command);
  NSLog(@"     open: %@", open);

  [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[notification.request.identifier]];

  BOOL success = YES;
  if (bundleID.length > 0) success &= [self activateAppWithBundleID:bundleID];
  if (command.length > 0) success &= [self executeShellCommand:command];
  if (open.length > 0) success &= [self openURLString:open];

  completionHandler();
  exit(success ? 0 : 1);
}

#pragma mark - Helpers

- (void)deferHelpUntilPendingResponse
{
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (!self.handledResponse) {
      [self printHelpBanner];
      exit(1);
    }
  });
}

- (BOOL)openURLString:(NSString *)urlString
{
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) {
    NSLog(@"Unable to construct URL from '%@'.", urlString);
    return NO;
  }

  if (url.scheme.length == 0) {
    url = [NSURL fileURLWithPath:urlString];
  }

  BOOL opened = [[NSWorkspace sharedWorkspace] openURL:url];
  if (!opened) {
    NSLog(@"Failed to open URL %@", urlString);
  }

  return opened;
}

- (BOOL)activateAppWithBundleID:(NSString *)bundleID
{
  NSArray<NSRunningApplication *> *runningApps = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID];
  NSRunningApplication *application = runningApps.firstObject;

  if (!application) {
    NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleID];
    if (!appURL) {
      NSLog(@"Unable to find an application with the specified bundle identifier %@.", bundleID);
      return NO;
    }

    NSError *launchError = nil;
    BOOL launched = [[NSWorkspace sharedWorkspace] launchApplicationAtURL:appURL
                                                                  options:(NSWorkspaceLaunchAsync | NSWorkspaceLaunchNewInstance)
                                                            configuration:@{}
                                                                    error:&launchError];
    if (!launched) {
      NSLog(@"Unable to launch application %@: %@", bundleID, launchError.localizedDescription);
      return NO;
    }
    runningApps = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID];
    application = runningApps.firstObject;
  }

  if (!application) {
    NSLog(@"Unable to activate application %@.", bundleID);
    return NO;
  }

  return [application activateWithOptions:NSApplicationActivateIgnoringOtherApps];
}

- (BOOL)executeShellCommand:(NSString *)command
{
  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
  task.arguments = @[@"-c", command];

  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;

  NSError *error = nil;
  BOOL launched = [task launchAndReturnError:&error];
  if (!launched) {
    NSLog(@"Unable to execute command '%@': %@", command, error.localizedDescription);
    return NO;
  }

  [task waitUntilExit];

  NSData *outputData = [[pipe fileHandleForReading] readDataToEndOfFile];
  if (outputData.length > 0) {
    NSString *outputString = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    if (outputString.length > 0) {
      NSLog(@"command output:\n%@", outputString);
    }
  }

  return task.terminationStatus == 0;
}

@end
