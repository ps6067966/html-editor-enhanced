export 'dart:html';

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html_editor_enhanced/html_editor.dart';
import 'package:html_editor_enhanced/utils/toolbar_icon.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:html_editor_enhanced/utils/shims/dart_ui.dart' as ui;

/// The HTML Editor widget itself, for web (uses IFrameElement)
class HtmlEditorWidget extends StatefulWidget {
  HtmlEditorWidget({
    Key? key,
    required this.widgetController,
    this.value,
    required this.height,
    required this.showBottomToolbar,
    this.hint,
    this.callbacks,
    required this.toolbar,
    required this.plugins,
    this.darkMode,
    required this.initBC,
  }) : super(key: key);

  final HtmlEditorController widgetController;
  final String? value;
  final double height;
  final bool showBottomToolbar;
  final String? hint;
  final UniqueKey webViewKey = UniqueKey();
  final Callbacks? callbacks;
  final List<Toolbar> toolbar;
  final List<Plugins> plugins;
  final bool? darkMode;
  final BuildContext initBC;

  _HtmlEditorWidgetWebState createState() => _HtmlEditorWidgetWebState();
}

/// State for the web Html editor widget
///
/// A stateful widget is necessary here, otherwise the IFrameElement will be
/// rebuilt excessively, hurting performance
class _HtmlEditorWidgetWebState extends State<HtmlEditorWidget> {
  /// The view ID for the IFrameElement. Must be unique.
  late String createdViewId;

  @override
  void initState() {
    createdViewId = getRandString(10);
    controllerMap[widget.widgetController] = createdViewId;
    super.initState();
    String summernoteToolbar = "[\n";
    String headString = "";
    String summernoteCallbacks = "callbacks: {";
    for (Toolbar t in widget.toolbar) {
      summernoteToolbar =
          summernoteToolbar + "['${t.getGroupName()}', ${t.getButtons(listStyles: widget.plugins.whereType<SummernoteListStyles>().isNotEmpty)}],\n";
    }
    if (widget.plugins.isNotEmpty) {
      summernoteToolbar = summernoteToolbar + "['plugins', [";
      for (Plugins p in widget.plugins) {
        summernoteToolbar = summernoteToolbar +
            (p.getToolbarString().isNotEmpty ? "'${p.getToolbarString()}'" : "") +
            (p == widget.plugins.last ? "]]\n" : p.getToolbarString().isNotEmpty ? ", " : "");
        headString = headString + p.getHeadString() + "\n";
        if (p is SummernoteAtMention) {
          summernoteCallbacks = summernoteCallbacks + """
            \nsummernoteAtMention: {
              getSuggestions: (value) => ${p.getMentions()},
              onSelect: (value) => {
                window.parent.postMessage(JSON.stringify({"view": "$createdViewId", "type": "toDart: onSelectMention", "value": value}), "*");
              },
            },
          """;
          if (p.onSelect != null) {
            html.window.onMessage.listen((event) {
              var data = json.decode(event.data);
              if (data["type"].contains("toDart:") && data["view"] == createdViewId
                  && data["type"].contains("onSelectMention")) {
                p.onSelect!.call(data["value"]);
              }
            });
          }
        }
        if (p is SummernoteFile) {
          if (p.onFileUpload != null) {
            summernoteCallbacks = summernoteCallbacks + """
                onFileUpload: function(files) {
                  window.parent.postMessage(JSON.stringify({"view": "$createdViewId", "messageType": "toDart: onFileUpload", "lastModified": files[0].lastModified, "lastModifiedDate": files[0].lastModifiedDate, "name": files[0].name, "size": files[0].size, "type": files[0].type}), "*");
                }
            """;
            html.window.onMessage.listen((event) {
              var data = json.decode(event.data);
              if (data["messageType"].contains("toDart:") && data["view"] == createdViewId
                  && data["messageType"].contains("onFileUpload")) {
                Map<String, dynamic> map = {
                  'lastModified': data["lastModified"],
                  'lastModifiedDate': data["lastModifiedDate"],
                  'name': data["name"],
                  'size': data["size"],
                  'type': data["type"]
                };
                String jsonStr = json.encode(map);
                FileUpload file = fileUploadFromJson(jsonStr);
                p.onFileUpload!.call(file);
              }
            });
          }
        }
      }
    }
    summernoteToolbar = summernoteToolbar + "],";
    summernoteCallbacks = summernoteCallbacks + "}";
    String darkCSS = "";
    if ((Theme.of(widget.initBC).brightness == Brightness.dark ||
            widget.darkMode == true) &&
        widget.darkMode != false) {
      darkCSS =
          "<link href=\"assets/packages/html_editor_enhanced/assets/summernote-lite-dark.css\" rel=\"stylesheet\">";
    }
    String jsCallbacks = "";
    if (widget.callbacks != null)
      jsCallbacks = getJsCallbacks(widget.callbacks!);
    String htmlString = """
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
        <meta name="description" content="Flutter Summernote HTML Editor">
        <meta name="author" content="tneotia">
        <title>Summernote Text Editor HTML</title>
        <script src="assets/packages/html_editor_enhanced/assets/jquery.min.js" type="application/javascript"></script>
        <link href="assets/packages/html_editor_enhanced/assets/summernote-lite.min.css" rel="stylesheet">
        <script src="assets/packages/html_editor_enhanced/assets/summernote-lite.min.js" type="application/javascript"></script>
        $darkCSS
      </head>
      <body>
      <div id="summernote-2"></div>
      $headString
      <script type="text/javascript">
        \$(document).ready(function () {
          \$('#summernote-2').summernote({
            placeholder: "${widget.hint}",
            tabsize: 2,
            height: ${widget.height - 125},
            maxHeight: ${widget.height - 125},
            toolbar: $summernoteToolbar
            disableGrammar: false,
            spellCheck: false,
            $summernoteCallbacks
          });
        });
       
        window.parent.addEventListener('message', handleMessage, false);
      
        function handleMessage(e) {
          if (e.data.includes("toIframe:")) {
            var data = JSON.parse(e.data);
            if (data["view"].includes("$createdViewId")) {
              if (data["type"].includes("getText")) {
                var str = \$('#summernote-2').summernote('code');
                window.parent.postMessage(JSON.stringify({"type": "toDart: getText", "text": str}), "*");
              }
              if (data["type"].includes("setText")) {
                \$('#summernote-2').summernote('code', data["text"]);
              }
              if (data["type"].includes("setFullScreen")) {
                \$("#summernote-2").summernote("fullscreen.toggle");
              }
              if (data["type"].includes("setFocus")) {
                \$('#summernote-2').summernote('focus');
              }
              if (data["type"].includes("clear")) {
                \$('#summernote-2').summernote('reset');
              }
              if (data["type"].includes("setHint")) {
                \$(".note-placeholder").html(data["text"]);
              }
              if (data["type"].includes("toggleCodeview")) {
                \$('#summernote-2').summernote('codeview.toggle');
              }
              if (data["type"].includes("disable")) {
                \$('#summernote-2').summernote('disable');
              }
              if (data["type"].includes("enable")) {
                \$('#summernote-2').summernote('enable');
              }
              if (data["type"].includes("undo")) {
                \$('#summernote-2').summernote('undo');
              }
              if (data["type"].includes("redo")) {
                \$('#summernote-2').summernote('redo');
              }
              if (data["type"].includes("insertText")) {
                \$('#summernote-2').summernote('insertText', data["text"]);
              }
              if (data["type"].includes("insertHtml")) {
                \$('#summernote-2').summernote('pasteHTML', data["html"]);
              }
              if (data["type"].includes("insertNetworkImage")) {
                \$('#summernote-2').summernote('insertImage', data["url"], data["filename"]);
              }
              if (data["type"].includes("insertLink")) {
                \$('#summernote-2').summernote('createLink', {
                  text: data["text"],
                  url: data["url"],
                  isNewWindow: data["isNewWindow"]
                });
              }
              if (data["type"].includes("reload")) {
                window.location.reload();
              }
            }
          }
        }
        
        $jsCallbacks
      </script>
      <style>
        body {
            display: block;
            margin: 0px;
        }
        .note-editor.note-airframe, .note-editor.note-frame {
            border: 0px solid #a9a9a9;
        }
        .note-frame {
            border-radius: 0px;
        }
      </style>
      </body>
      </html>
    """;
    final html.IFrameElement iframe = html.IFrameElement()
      ..width = MediaQuery.of(widget.initBC).size.width.toString() //'800'
      ..height = widget.height.toString()
      ..srcdoc = htmlString
      ..style.border = 'none'
      ..onLoad.listen((event) async {
        if (widget.callbacks?.onInit != null) widget.callbacks!.onInit!.call();
        if (widget.value != null)
          widget.widgetController.setText(widget.value!);
      });
    if (widget.callbacks != null) addJSListener(widget.callbacks!);
    ui.platformViewRegistry
        .registerViewFactory(createdViewId, (int viewId) => iframe);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
            child: Directionality(
                textDirection: TextDirection.ltr,
                child: HtmlElementView(
                  viewType: createdViewId,
                ))),
        widget.showBottomToolbar
            ? Divider(height: 0)
            : Container(height: 0, width: 0),
        widget.showBottomToolbar
            ? Padding(
                padding:
                    const EdgeInsets.only(left: 4, right: 4, bottom: 8, top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    toolbarIcon(context, Icons.content_copy, "Copy",
                        onTap: () async {
                      String? data = await widget.widgetController.getText();
                      Clipboard.setData(new ClipboardData(text: data));
                    }),
                    toolbarIcon(context, Icons.content_paste, "Paste",
                        onTap: () async {
                      ClipboardData? data =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      if (data != null) {
                        String txtIsi = data.text!
                            .replaceAll("'", '\\"')
                            .replaceAll('"', '\\"')
                            .replaceAll("[", "\\[")
                            .replaceAll("]", "\\]")
                            .replaceAll("\n", "<br/>")
                            .replaceAll("\n\n", "<br/>")
                            .replaceAll("\r", " ")
                            .replaceAll('\r\n', " ");
                        widget.widgetController.insertHtml(txtIsi);
                      }
                    }),
                  ],
                ),
              )
            : Container(height: 0, width: 0),
      ],
    );
  }

  /// Adds the callbacks the user set into JavaScript
  String getJsCallbacks(Callbacks c) {
    String callbacks = "";
    if (c.onChange != null) {
      callbacks = callbacks +
          """
          \$('#summernote-2').on('summernote.change', function(_, contents, \$editable) {
            window.parent.postMessage(JSON.stringify({"view": "$createdViewId", "type": "toDart: onChange", "contents": contents}), "*");
          });\n
        """;
    }
    if (c.onEnter != null) {
      callbacks = callbacks +
          """
          \$('#summernote-2').on('summernote.enter', function() {
            window.parent.postMessage(JSON.stringify({"view": "$createdViewId", "type": "toDart: onEnter"}), "*");
          });\n
        """;
    }
    if (c.onFocus != null) {
      callbacks = callbacks +
          """
          \$('#summernote-2').on('summernote.focus', function() {
            window.parent.postMessage(JSON.stringify({"view": "$createdViewId", "type": "toDart: onFocus"}), "*");
          });\n
        """;
    }
    if (c.onBlur != null) {
      callbacks = callbacks +
          """
          \$('#summernote-2').on('summernote.blur', function() {
            window.parent.postMessage(JSON.stringify({"view": "$createdViewId", "type": "toDart: onBlur"}), "*");
          });\n
        """;
    }
    if (c.onBlurCodeview != null) {
      callbacks = callbacks +
          """
          \$('#summernote-2').on('summernote.blur.codeview', function() {
            window.parent.postMessage(JSON.stringify({"view": "$createdViewId", "type": "toDart: onBlurCodeview"}), "*");
          });\n
        """;
    }
    if (c.onKeyDown != null) {
      callbacks = callbacks +
          """
          \$('#summernote-2').on('summernote.keydown', function(_, e) {
            window.parent.postMessage(JSON.stringify({"view": "$createdViewId", "type": "toDart: onKeyDown", "keyCode": e.keyCode}), "*");
          });\n
        """;
    }
    if (c.onKeyUp != null) {
      callbacks = callbacks +
          """
          \$('#summernote-2').on('summernote.keyup', function(_, e) {
            window.parent.postMessage(JSON.stringify({"view": "$createdViewId", "type": "toDart: onKeyUp", "keyCode": e.keyCode}), "*");
          });\n
        """;
    }
    if (c.onPaste != null) {
      callbacks = callbacks +
          """
          \$('#summernote-2').on('summernote.paste', function(_) {
            window.parent.postMessage(JSON.stringify({"view": "$createdViewId", "type": "toDart: onPaste"}), "*");
          });\n
        """;
    }
    return callbacks;
  }

  /// Adds an event listener to check when a callback is fired
  void addJSListener(Callbacks c) {
    html.window.onMessage.listen((event) {
      var data = json.decode(event.data);
      if (data["type"].contains("toDart:") && data["view"] == createdViewId) {
        if (data["type"].contains("onChange")) {
          c.onChange!.call(data["contents"]);
        }
        if (data["type"].contains("onEnter")) {
          c.onEnter!.call();
        }
        if (data["type"].contains("onFocus")) {
          c.onFocus!.call();
        }
        if (data["type"].contains("onBlur")) {
          c.onBlur!.call();
        }
        if (data["type"].contains("onBlurCodeview")) {
          c.onBlurCodeview!.call();
        }
        if (data["type"].contains("onKeyDown")) {
          c.onKeyDown!.call(data["keyCode"]);
        }
        if (data["type"].contains("onKeyUp")) {
          c.onKeyUp!.call(data["keyCode"]);
        }
        if (data["type"].contains("onPaste")) {
          c.onPaste!.call();
        }
      }
    });
  }

  /// Generates a random string to be used as the view ID. Technically this
  /// limits the number of editors to a finite length, but nobody will be
  /// embedding enough editors to reach the theoretical limit (yes, this
  /// is a challenge ;-) )
  String getRandString(int len) {
    var random = Random.secure();
    var values = List<int>.generate(len, (i) => random.nextInt(255));
    return base64UrlEncode(values);
  }
}