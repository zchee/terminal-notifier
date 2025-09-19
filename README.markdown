# terminal-notifier

[![GitHub release](https://img.shields.io/github/release/julienXX/terminal-notifier.svg)](https://github.com/julienXX/terminal-notifier/releases)

terminal-notifier is a command-line tool to send macOS User Notifications,
which are available on macOS 10.14 and higher as of the current release.


## News

[alerter](https://github.com/vjeantet/alerter) features were merged in terminal-notifier 1.7. This led to some issues and even more issues in the 1.8 release. We decided with [Valère Jeantet](https://github.com/vjeantet) to rollback this merge.

From now on terminal-notifier won't have the sticky notification feature nor the actions buttons. If you need them please use [alerter](https://github.com/vjeantet/alerter). I also want to follow [semver](http://semver.org) hence this latest version starts at 2.0.0.

Sticking to two smaller specialized tools will hopefully make them easier to maintain and less error prone.


## Caveats

* It is currently packaged as an application bundle, because `NSUserNotification`
  does not work from a ‘Foundation tool’. [radar://11956694](radar://11956694)

* Beginning with 2.x, terminal-notifier uses the modern `UserNotifications` framework. This requires macOS 10.14 or newer and removes the private API overrides that earlier builds relied on.

* If you need to target macOS releases earlier than 10.14, stick to terminal-notifier 2.0.0 or earlier.

* If you're looking for sticky notifications or more actions on a notification please use [alerter](https://github.com/vjeantet/alerter)

## Download

Prebuilt binaries are available from the
[releases section](https://github.com/julienXX/terminal-notifier/releases).

Or if you want to use this from
[Ruby](https://github.com/julienXX/terminal-notifier/tree/master/Ruby), you can
install it through RubyGems:

```
$ [sudo] gem install terminal-notifier
```

You can also install it via [Homebrew](https://github.com/mxcl/homebrew):
```
$ brew install terminal-notifier
```

## Usage

```
$ ./terminal-notifier.app/Contents/MacOS/terminal-notifier -[message|group|list] [VALUE|ID|ID] [options]
```

In order to use terminal-notifier, you have to call the binary _inside_ the
application bundle.

The Ruby gem, which wraps this tool, _does_ have a bin wrapper. If installed
you can simply do:

```
$ terminal-notifier -[message|group|list] [VALUE|ID|ID] [options]
```

This will obviously be a bit slower than using the tool without the wrapper.

If you'd like notifications to stay on the screen until dismissed, go to System Preferences -> Notifications -> terminal-notifier and change the style from Banners to Alerts. You cannot do this on a per-notification basis.


### Example Uses

Display piped data with a sound:
```
$ echo 'Piped Message Data!' | terminal-notifier -sound default
```

![Example 1](assets/Example_1.png)

Use a custom icon:
```
$ terminal-notifier -title ProjectX -subtitle "new tag detected" -message "Finished" -appIcon http://vjeantet.fr/images/logo.png
```

![Example 3](assets/Example_3.png)

Open an URL when the notification is clicked:
```
$ terminal-notifier -title '💰' -message 'Check your Apple stock!' -open 'http://finance.yahoo.com/q?s=AAPL'
```

![Example 4](assets/Example_4.png)

Open an app when the notification is clicked:
```
$ terminal-notifier -group 'address-book-sync' -title 'Address Book Sync' -subtitle 'Finished' -message 'Imported 42 contacts.' -activate 'com.apple.AddressBook'
```

![Example 5](assets/Example_5.png)


### Options

At a minimum, you must specify either the `-message` , the `-remove`, or the
`-list` option.

-------------------------------------------------------------------------------

`-message VALUE`  **[required]**

The message body of the notification.

If you pipe data into terminal-notifier, you can omit this option,
and the piped data will become the message body instead.

-------------------------------------------------------------------------------

`-title VALUE`

The title of the notification. This defaults to ‘Terminal’.

-------------------------------------------------------------------------------

`-subtitle VALUE`

The subtitle of the notification.

-------------------------------------------------------------------------------

`-sound NAME`

Play the `NAME` sound when the notification appears.
Sound names are listed in `/System/Library/Sounds`.

Use the special `NAME` “default” for the default notification sound.

-------------------------------------------------------------------------------

`-group ID`

Specifies the notification’s ‘group’. For any ‘group’, only _one_
notification will ever be shown, replacing previously posted notifications.

A notification can be explicitly removed with the `-remove` option (see
below).

Example group IDs:

* The sender’s name (to scope the notifications by tool).
* The sender’s process ID (to scope the notifications by a unique process).
* The current working directory (to scope notifications by project).

-------------------------------------------------------------------------------

`-remove ID`  **[required]**

Remove a previous notification from the `ID` ‘group’, if one exists.

Use the special `ID` “ALL” to remove all messages.

-------------------------------------------------------------------------------

`-list ID` **[required]**

Lists details about the specified ‘group’ `ID`.

Use the special `ID` “ALL” to list details about all currently active messages.

The output of this command is tab-separated, which makes it easy to parse.

-------------------------------------------------------------------------------

`-activate ID`

Activate the application specified by `ID` when the user clicks the
notification.

You can find the bundle identifier (`CFBundleIdentifier`) of an application in its `Info.plist` file
_inside_ the application bundle.

Examples application IDs are:

* `com.apple.Terminal` to activate Terminal.app
* `com.apple.Safari` to activate Safari.app

-------------------------------------------------------------------------------

`-sender ID`

Requests that the notification appear to come from the application identified by
`ID`. Because macOS now enforces bundle identities at runtime, you must
code-sign the helper with the desired bundle identifier before this flag will be
honoured.

Typical workflow:

1. Duplicate the app bundle: `cp -R terminal-notifier.app MyNotifier.app`
2. Update the bundle identifier: `/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.example.sender" MyNotifier.app/Contents/Info.plist`
3. (Optional) Replace `MyNotifier.app/Contents/Resources/AppIcon.icns` with the icon you want macOS to display.
4. Codesign it with a certificate that matches that identifier:
   `codesign --force --deep --options runtime --sign "Apple Development: Your Name" MyNotifier.app`

Once the helper is signed, `-sender com.example.sender` will be accepted and the
system will display the icon associated with that signed bundle. Without these
steps the option is ignored and a warning is logged.

Because the notification now launches that application when clicked, `-sender`
still cannot be combined with `-execute` or `-activate`.

For information on the `ID`, see the `-activate` option.

-------------------------------------------------------------------------------

`-appIcon PATH`

Attach an additional image to the notification. macOS no longer allows
terminal-notifier to override its application icon at runtime; instead the image
is delivered as an attachment alongside the notification content. Prefer
`-contentImage` for richer layouts.

-------------------------------------------------------------------------------

`-contentImage PATH`

Specify an image `PATH` to attach inside of the notification.

**WARNING: This option is subject to change since it relies on a private method.**

-------------------------------------------------------------------------------

`-open URL`

Open `URL` when the user clicks the notification. This can be a web or file URL,
or any custom URL scheme.

-------------------------------------------------------------------------------

`-execute COMMAND`

Run the shell command `COMMAND` when the user clicks the notification.

-------------------------------------------------------------------------------

`-ignoreDnD`

Ignore Do Not Disturb settings and unconditionally show the notification.

**WARNING: This option is subject to change since it relies on a private method.**

## License

All the works are available under the MIT license. **Except** for
‘Terminal.icns’, which is a copy of Apple’s Terminal.app icon and as such is
copyright of Apple.

Copyright (C) 2012-2017 Eloy Durán <eloy.de.enige@gmail.com>, Julien Blanchard
<julien@sideburns.eu>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
