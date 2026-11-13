package {
import flash.display.Sprite;
import flash.events.KeyboardEvent;
import flash.events.MouseEvent;
import flash.external.ExternalInterface;
import flash.text.TextField;
import flash.text.TextFieldType;
import flash.text.TextFormat;

// Up, Down, PageUp and PageDown (with and without Shift) in a multiline input field.
// All lines are made of the same character, so a column is at the same x on every line,
// whatever the font. After each key, the caret and the selection are printed as line:column.
public class Test extends Sprite {
    private var tf:TextField;
    private var step:int = 0;

    // [text, caret line, caret column, keys]
    private var cases:Array;

    public function Test() {
        var ten:String = "aaaaaaaaaa";
        var lines:Array = [];
        for (var i:int = 0; i < 12; i++) {
            lines.push(ten);
        }
        var words:Array = [];
        for (i = 0; i < 40; i++) {
            words.push("aaaa");
        }
        cases = [
            [lines.join("\r"), 2, 5, ["Up", "Up", "Up", "Down", "Down", "Shift+Down", "Shift+Up", "Shift+Up"]],
            [lines.join("\r"), 6, 5, ["PageUp", "PageDown", "PageDown", "PageDown", "Shift+PageUp", "PageDown", "PageDown"]],
            [ten + "\r" + "aaa" + "\r" + ten + "\r" + ten, 0, 8, ["Down", "Down", "Down", "Down", "Up", "Up"]],
            [ten + "\r" + ten, 1, 10, ["Up", "Up", "Down", "Down"]],
            [words.join(" "), 1, 7, ["Up", "Down", "Down", "Shift+Up"]]
        ];

        tf = new TextField();
        tf.type = TextFieldType.INPUT;
        tf.multiline = true;
        tf.wordWrap = true;
        tf.border = true;
        tf.defaultTextFormat = new TextFormat("_sans", 12);
        tf.width = 190;
        tf.height = 70;
        addChild(tf);

        tf.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
            setUp(false);
        });
        tf.addEventListener(KeyboardEvent.KEY_UP, keyUp);
        stage.focus = tf;
        setUp(true);
    }

    private function out(s:String):void {
        trace(s);
        if (ExternalInterface.available) {
            ExternalInterface.call("__out", s);
        }
    }

    private function current():Array {
        var n:int = 0;
        for (var i:int = 0; i < cases.length; i++) {
            if (step < n + cases[i][3].length) {
                return [i, step - n];
            }
            n += cases[i][3].length;
        }
        return null;
    }

    private function setUp(print:Boolean):void {
        var c:Array = current();
        if (c == null || c[1] != 0) {
            return;
        }
        var data:Array = cases[c[0]];
        tf.text = data[0];
        tf.scrollV = 1;
        var p:int = tf.getLineOffset(data[1]) + data[2];
        tf.setSelection(p, p);
        if (print) {
            out("case " + c[0] + ": lines=" + tf.numLines + " visible=" + (tf.bottomScrollV - tf.scrollV + 1) +
                " caret=" + pos(p));
        }
    }

    private function pos(i:int):String {
        var line:int = i >= tf.length ? tf.numLines - 1 : tf.getLineIndexOfChar(i);
        return line + ":" + (i - tf.getLineOffset(line));
    }

    private function keyUp(e:KeyboardEvent):void {
        if (e.keyCode == 16 || e.keyCode == 17) {
            return;
        }
        var c:Array = current();
        if (c == null) {
            return;
        }
        out("  " + cases[c[0]][3][c[1]] + ": caret=" + pos(tf.caretIndex) +
            " sel=" + pos(tf.selectionBeginIndex) + "-" + pos(tf.selectionEndIndex));
        step++;
        setUp(true);
    }
}
}
