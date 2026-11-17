package {
import flash.display.Sprite;
import flash.events.KeyboardEvent;
import flash.events.MouseEvent;
import flash.external.ExternalInterface;
import flash.text.TextField;
import flash.text.TextFieldType;
import flash.text.TextFormat;

// Home, End, Shift+Home and Shift+End in a multiline input field.
// The caret is placed in the middle of the second line, then one key is pressed.
// Lines are separated by "\r" (what Enter inserts), by "\n", or come from word wrapping.
// After each key, the selection is printed both as indices and relative to the line:
// S = start of the caret's line, E = end of that line (before its line break), P = initial caret.
public class Test extends Sprite {
    private var tf:TextField;
    private var step:int = 0;

    private var texts:Array = [
        "line one\rline two\rline three",
        "line one\nline two\nline three",
        "word word word word word word word word word word word word word word word word word word"
    ];
    private var keys:Array = ["Home", "End", "Shift+End", "Shift+Home"];

    public function Test() {
        tf = new TextField();
        tf.type = TextFieldType.INPUT;
        tf.multiline = true;
        tf.wordWrap = true;
        tf.border = true;
        tf.defaultTextFormat = new TextFormat("_sans", 12);
        tf.width = 190;
        tf.height = 150;
        addChild(tf);

        tf.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
            setUp();
        });
        tf.addEventListener(KeyboardEvent.KEY_UP, keyUp);
        stage.focus = tf;
        setUp();
    }

    private function out(s:String):void {
        trace(s);
        if (ExternalInterface.available) {
            ExternalInterface.call("__out", s);
        }
    }

    private function caseIndex():int {
        return int(step / keys.length);
    }

    private function initialPosition():int {
        if (caseIndex() == 2) {
            return tf.getLineOffset(1) + 6;
        }
        return 12;
    }

    private function setUp():void {
        if (caseIndex() >= texts.length) {
            return;
        }
        tf.text = texts[caseIndex()];
        var p:int = initialPosition();
        tf.setSelection(p, p);
    }

    private function label(i:int, s:int, e:int, p:int):String {
        if (i == s) return "S";
        if (i == e) return "E";
        if (i == p) return "P";
        return String(i);
    }

    private function keyUp(e:KeyboardEvent):void {
        if (e.keyCode == 16 || e.keyCode == 17) {
            return;
        }
        if (caseIndex() >= texts.length) {
            return;
        }
        var p:int = initialPosition();
        var line:int = tf.getLineIndexOfChar(p);
        var start:int = tf.getLineOffset(line);
        var end:int = start + tf.getLineLength(line);
        var last:String = tf.text.charAt(end - 1);
        if (last == "\r" || last == "\n") {
            end--;
        }
        var b:int = tf.selectionBeginIndex;
        var en:int = tf.selectionEndIndex;
        var msg:String = "case " + caseIndex() + " " + keys[step % keys.length] +
            ": sel=" + label(b, start, end, p) + "," + label(en, start, end, p) +
            " caret=" + label(tf.caretIndex, start, end, p);
        if (caseIndex() < 2) {
            msg += " (" + b + "," + en + ")";
        }
        out(msg);
        step++;
        setUp();
    }
}
}
