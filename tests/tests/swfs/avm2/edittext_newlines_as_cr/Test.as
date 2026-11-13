package {
import flash.display.Sprite;
import flash.events.KeyboardEvent;
import flash.events.MouseEvent;
import flash.events.TimerEvent;
import flash.external.ExternalInterface;
import flash.system.System;
import flash.text.TextField;
import flash.text.TextFieldType;
import flash.utils.Timer;

// Line breaks given to a text field: Flash Player stores "\n" as "\r", through the text
// setter, appendText, replaceText, replaceSelectedText, and when pasting.
public class Test extends Sprite {
    private static const CLIPBOARD:String = "l1\nl2\r\nl3";
    private var tf:TextField;

    public function Test() {
        tf = new TextField();
        tf.type = TextFieldType.INPUT;
        tf.multiline = true;
        tf.width = 150;
        tf.height = 150;
        tf.border = true;
        addChild(tf);
        stage.focus = tf;
        tf.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
            // In the browser plugin, the clipboard can only be set from a user event.
            System.setClipboard(CLIPBOARD);
            tf.text = "";
        });
        tf.addEventListener(KeyboardEvent.KEY_UP, function(e:KeyboardEvent):void {
            if (e.keyCode == 86) {
                out("pasted " + codes(CLIPBOARD) + " -> " + codes(tf.text));
            }
        });
        // Wait a bit so that the output also reaches the page in the browser plugin.
        var t:Timer = new Timer(500, 1);
        t.addEventListener(TimerEvent.TIMER, run);
        t.start();
    }

    private function out(s:String):void {
        trace(s);
        if (ExternalInterface.available) {
            ExternalInterface.call("__out", s);
        }
    }

    private function codes(s:String):String {
        var r:String = "";
        for (var i:int = 0; i < s.length; i++) {
            var c:int = s.charCodeAt(i);
            r += c == 13 ? "<CR>" : c == 10 ? "<LF>" : (c < 32 || c > 126) ? "<" + c + ">" : s.charAt(i);
        }
        return r;
    }

    private function run(e:TimerEvent):void {
        var texts:Array = ["a\nb", "a\rb", "a\r\nb", "a\n\nb", "\n"];
        for each (var s:String in texts) {
            tf.text = s;
            out("text = " + codes(s) + " -> " + codes(tf.text) + " length=" + tf.length + " numLines=" + tf.numLines);
        }
        tf.text = "x";
        tf.appendText("1\n2\r\n3");
        out("appendText -> " + codes(tf.text));
        tf.text = "abc";
        tf.replaceText(1, 2, "\n-\r\n");
        out("replaceText -> " + codes(tf.text));
        tf.text = "abc";
        tf.setSelection(1, 2);
        tf.replaceSelectedText("\n-\r\n");
        out("replaceSelectedText -> " + codes(tf.text));
        tf.text = "";
        out("ready");
    }
}
}
