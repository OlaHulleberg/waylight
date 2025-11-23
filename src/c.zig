// Shared C imports to avoid type conflicts (GTK4 + gtk4-layer-shell + WebKitGTK 6.0)
const c_imports = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("gtk4-layer-shell.h");
    @cInclude("webkitgtk-6.0/webkit/webkit.h");
});

// Re-export all C symbols
pub const gtk_init = c_imports.gtk_init;
pub const gtk_window_new = c_imports.gtk_window_new;
pub const gtk_window_set_decorated = c_imports.gtk_window_set_decorated;
pub const gtk_window_set_default_size = c_imports.gtk_window_set_default_size;
pub const gtk_window_set_child = c_imports.gtk_window_set_child; // GTK4
pub const gtk_widget_set_visible = c_imports.gtk_widget_set_visible;
pub const gtk_widget_show = c_imports.gtk_widget_show;
pub const gtk_box_new = c_imports.gtk_box_new;
pub const gtk_box_append = c_imports.gtk_box_append;

// GTK4 Layer Shell functions
pub const gtk_layer_init_for_window = c_imports.gtk_layer_init_for_window;
pub const gtk_layer_set_layer = c_imports.gtk_layer_set_layer;
pub const gtk_layer_set_keyboard_mode = c_imports.gtk_layer_set_keyboard_mode;
pub const gtk_layer_set_anchor = c_imports.gtk_layer_set_anchor;
pub const gtk_layer_set_margin = c_imports.gtk_layer_set_margin;
pub const gtk_layer_set_namespace = c_imports.gtk_layer_set_namespace;
pub const GTK_LAYER_SHELL_LAYER_OVERLAY = c_imports.GTK_LAYER_SHELL_LAYER_OVERLAY;
pub const GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE = c_imports.GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE;
pub const GTK_LAYER_SHELL_EDGE_TOP = c_imports.GTK_LAYER_SHELL_EDGE_TOP;
pub const GTK_LAYER_SHELL_EDGE_BOTTOM = c_imports.GTK_LAYER_SHELL_EDGE_BOTTOM;
pub const GTK_LAYER_SHELL_EDGE_LEFT = c_imports.GTK_LAYER_SHELL_EDGE_LEFT;
pub const GTK_LAYER_SHELL_EDGE_RIGHT = c_imports.GTK_LAYER_SHELL_EDGE_RIGHT;

// Main loop
pub const GMainLoop = c_imports.GMainLoop;
pub const g_main_loop_new = c_imports.g_main_loop_new;
pub const g_main_loop_run = c_imports.g_main_loop_run;
pub const g_main_loop_quit = c_imports.g_main_loop_quit;

// Event controller for keyboard
pub const gtk_event_controller_key_new = c_imports.gtk_event_controller_key_new;
pub const gtk_widget_add_controller = c_imports.gtk_widget_add_controller;
pub const g_signal_connect_data = c_imports.g_signal_connect_data;
pub const GDK_KEY_Escape = c_imports.GDK_KEY_Escape;
pub const GtkEventControllerKey = c_imports.GtkEventControllerKey;

// Window close
pub const gtk_window_close = c_imports.gtk_window_close;
pub const gtk_window_destroy = c_imports.gtk_window_destroy;

pub const webkit_web_view_new = c_imports.webkit_web_view_new;
pub const webkit_web_view_set_background_color = c_imports.webkit_web_view_set_background_color;
pub const webkit_web_view_load_html = c_imports.webkit_web_view_load_html;
pub const webkit_web_view_load_uri = c_imports.webkit_web_view_load_uri;
pub const webkit_web_view_evaluate_javascript = c_imports.webkit_web_view_evaluate_javascript;

pub const GtkWidget = c_imports.GtkWidget;
pub const GtkWindow = c_imports.GtkWindow;
pub const GtkBox = c_imports.GtkBox;
pub const WebKitWebView = c_imports.WebKitWebView;
pub const GdkRGBA = c_imports.GdkRGBA;
pub const GTK_ORIENTATION_VERTICAL = c_imports.GTK_ORIENTATION_VERTICAL;

// Widget sizing
pub const gtk_widget_set_hexpand = c_imports.gtk_widget_set_hexpand;
pub const gtk_widget_set_vexpand = c_imports.gtk_widget_set_vexpand;

// WebContext and custom URI scheme
pub const WebKitWebContext = c_imports.WebKitWebContext;
pub const webkit_web_context_new = c_imports.webkit_web_context_new;
pub const webkit_web_context_register_uri_scheme = c_imports.webkit_web_context_register_uri_scheme;
pub const webkit_web_view_get_context = c_imports.webkit_web_view_get_context;

// URI Scheme Request
pub const WebKitURISchemeRequest = c_imports.WebKitURISchemeRequest;
pub const webkit_uri_scheme_request_get_path = c_imports.webkit_uri_scheme_request_get_path;
pub const webkit_uri_scheme_request_get_uri = c_imports.webkit_uri_scheme_request_get_uri;
pub const webkit_uri_scheme_request_finish = c_imports.webkit_uri_scheme_request_finish;
pub const webkit_uri_scheme_request_finish_error = c_imports.webkit_uri_scheme_request_finish_error;

// GLib memory stream
pub const GInputStream = c_imports.GInputStream;
pub const g_memory_input_stream_new_from_data = c_imports.g_memory_input_stream_new_from_data;
pub const g_object_unref = c_imports.g_object_unref;
pub const g_object_new = c_imports.g_object_new;

// GError
pub const GError = c_imports.GError;
pub const g_error_new_literal = c_imports.g_error_new_literal;
pub const g_error_free = c_imports.g_error_free;
pub const g_quark_from_string = c_imports.g_quark_from_string;

// GLib memory allocation
pub const g_malloc = c_imports.g_malloc;

// CSS Provider for transparent window
pub const GtkCssProvider = c_imports.GtkCssProvider;
pub const gtk_css_provider_new = c_imports.gtk_css_provider_new;
pub const gtk_css_provider_load_from_string = c_imports.gtk_css_provider_load_from_string;
pub const gtk_style_context_add_provider_for_display = c_imports.gtk_style_context_add_provider_for_display;
pub const gtk_widget_get_display = c_imports.gtk_widget_get_display;
pub const GTK_STYLE_PROVIDER_PRIORITY_APPLICATION = c_imports.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION;

// WebKit User Content Manager (for JS ↔ Zig communication)
pub const WebKitUserContentManager = c_imports.WebKitUserContentManager;
pub const webkit_web_view_get_user_content_manager = c_imports.webkit_web_view_get_user_content_manager;
pub const webkit_user_content_manager_register_script_message_handler = c_imports.webkit_user_content_manager_register_script_message_handler;

// JavaScriptCore value handling
pub const JSCValue = c_imports.JSCValue;
pub const WebKitJavascriptResult = c_imports.WebKitJavascriptResult;
pub const jsc_value_to_string = c_imports.jsc_value_to_string;
pub const g_free = c_imports.g_free;

// WebKit Settings (for enabling file:// access)
pub const WebKitSettings = c_imports.WebKitSettings;
pub const webkit_web_view_get_settings = c_imports.webkit_web_view_get_settings;
pub const webkit_settings_set_allow_file_access_from_file_urls = c_imports.webkit_settings_set_allow_file_access_from_file_urls;
pub const webkit_settings_set_allow_universal_access_from_file_urls = c_imports.webkit_settings_set_allow_universal_access_from_file_urls;
