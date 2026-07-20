#import <Cocoa/Cocoa.h>

static volatile int chicago_editor_pending_command = 0;
static char chicago_editor_picker_path[4096];

static const char *chicago_copy_picker_url(NSURL *url) {
    chicago_editor_picker_path[0] = 0;
    if (!url) return chicago_editor_picker_path;
    const char *path = url.fileSystemRepresentation;
    if (!path) return chicago_editor_picker_path;
    strlcpy(chicago_editor_picker_path, path, sizeof(chicago_editor_picker_path));
    return chicago_editor_picker_path;
}

const char *chicago_editor_open_file(const char *title) {
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseFiles = YES; panel.canChooseDirectories = NO; panel.allowsMultipleSelection = NO;
    if (title) panel.title = [NSString stringWithUTF8String:title];
    return [panel runModal] == NSModalResponseOK ? chicago_copy_picker_url(panel.URL) : chicago_copy_picker_url(nil);
}

const char *chicago_editor_select_directory(const char *title) {
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseFiles = NO; panel.canChooseDirectories = YES; panel.allowsMultipleSelection = NO; panel.canCreateDirectories = YES;
    if (title) panel.title = [NSString stringWithUTF8String:title];
    return [panel runModal] == NSModalResponseOK ? chicago_copy_picker_url(panel.URL) : chicago_copy_picker_url(nil);
}

const char *chicago_editor_save_file(const char *title, const char *suggested) {
    NSSavePanel *panel = [NSSavePanel savePanel]; panel.canCreateDirectories = YES;
    if (title) panel.title = [NSString stringWithUTF8String:title];
    if (suggested) panel.nameFieldStringValue = [NSString stringWithUTF8String:suggested];
    return [panel runModal] == NSModalResponseOK ? chicago_copy_picker_url(panel.URL) : chicago_copy_picker_url(nil);
}

bool chicago_editor_reveal_path(const char *path) {
    if (!path) return false;
    NSString *value = [NSString stringWithUTF8String:path];
    if (!value.length) return false;
    NSURL *url = [NSURL fileURLWithPath:value];
    if (![[NSFileManager defaultManager] fileExistsAtPath:value]) return false;
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[url]];
    return true;
}

@interface ChicagoEditorMenuTarget : NSObject
- (void)openBuildMode:(id)sender;
- (void)openGraphMode:(id)sender;
- (void)exitEditor:(id)sender;
@end

@implementation ChicagoEditorMenuTarget
- (void)openBuildMode:(id)sender { (void)sender; chicago_editor_pending_command = 1; }
- (void)openGraphMode:(id)sender { (void)sender; chicago_editor_pending_command = 2; }
- (void)exitEditor:(id)sender { (void)sender; chicago_editor_pending_command = 3; }
@end

void chicago_editor_menu_install(void) {
    static ChicagoEditorMenuTarget *target;
    if (target || !NSApp) return;
    target = [ChicagoEditorMenuTarget new];
    NSMenu *main = NSApp.mainMenu;
    if (!main) { main = [NSMenu new]; NSApp.mainMenu = main; }
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:@"Editor" action:nil keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Editor"];
    NSMenuItem *build = [[NSMenuItem alloc] initWithTitle:@"Build Mode" action:@selector(openBuildMode:) keyEquivalent:@"1"];
    NSMenuItem *graph = [[NSMenuItem alloc] initWithTitle:@"Graph Mode" action:@selector(openGraphMode:) keyEquivalent:@"2"];
    build.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    graph.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    build.target = target; graph.target = target;
    [menu addItem:build]; [menu addItem:graph]; [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *exit = [[NSMenuItem alloc] initWithTitle:@"Exit Editor" action:@selector(exitEditor:) keyEquivalent:@""];
    exit.target = target; [menu addItem:exit]; root.submenu = menu; [main addItem:root];
}

int chicago_editor_menu_poll(void) {
    int command = chicago_editor_pending_command;
    chicago_editor_pending_command = 0;
    return command;
}
