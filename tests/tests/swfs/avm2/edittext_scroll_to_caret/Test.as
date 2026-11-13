package {
import flash.display.Sprite;
import flash.events.Event;
import flash.events.KeyboardEvent;
import flash.events.MouseEvent;
import flash.external.ExternalInterface;
import flash.text.TextField;
import flash.text.TextFieldType;
import flash.text.TextFormat;

// A text field scrolls to keep the caret visible while the user types and moves it.
// Field "a" is multiline and shows 4 lines: Enter, typing and the arrow, Home/End and page
// keys must change scrollV so that the caret's line stays visible.
// Field "b" is a narrow single line field: typing past its right edge, Home and End must
// change scrollH so that the caret stays visible. Its exact scrollH depends on the font, so
// only whether the caret is visible is printed.
public class Test extends Sprite {
    private var a:TextField;
    private var b:TextField;
    private var bLength:int = 0;
    private var bChanges:int = 0;
    private var bHidden:int = 0;

    public function Test() {
        a = field(5, 5, 190, 70, true);
        a.text = "line 1\rline 2\rline 3\rline 4";
        b = field(5, 90, 80, 20, false);

        a.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
            a.setSelection(a.length, a.length);
        });
        a.addEventListener(KeyboardEvent.KEY_UP, keyUpA);
        b.addEventListener(KeyboardEvent.KEY_UP, keyUpB);
        addEventListener(Event.ENTER_FRAME, enterFrame);
        stage.focus = a;
        a.setSelection(a.length, a.length);
        stateA("start");
    }

    private function field(x:int, y:int, w:int, h:int, multiline:Boolean):TextField {
        var tf:TextField = new TextField();
        tf.type = TextFieldType.INPUT;
        tf.multiline = multiline;
        tf.wordWrap = multiline;
        tf.border = true;
        tf.defaultTextFormat = new TextFormat("_sans", 12);
        tf.x = x;
        tf.y = y;
        tf.width = w;
        tf.height = h;
        addChild(tf);
        return tf;
    }

    private function out(s:String):void {
        trace(s);
        if (ExternalInterface.available) {
            ExternalInterface.call("__out", s);
        }
    }

    private function caretLine(tf:TextField):int {
        return tf.caretIndex >= tf.length ? tf.numLines - 1 : tf.getLineIndexOfChar(tf.caretIndex);
    }

    private function stateA(what:String):void {
        out("a " + what + ": lines=" + a.numLines + " caretLine=" + caretLine(a) + " scrollV=" + a.scrollV +
            " bottomScrollV=" + a.bottomScrollV);
    }

    private function keyName(e:KeyboardEvent):String {
        var names:Object = {13: "Enter", 33: "PageUp", 34: "PageDown", 35: "End", 36: "Home", 38: "Up", 40: "Down"};
        return names[e.keyCode] || String(e.keyCode);
    }

    private function keyUpA(e:KeyboardEvent):void {
        if (e.keyCode == 16 || e.keyCode == 17) {
            return;
        }
        stateA(keyName(e));
        if (e.keyCode == 34) {
            stage.focus = b;
            b.setSelection(0, 0);
        }
    }

    // Caret x, in the coordinates of getCharBoundaries (which ignore scrollH).
    private function caretX():Number {
        if (b.caretIndex == 0) {
            return 2;
        }
        return b.getCharBoundaries(b.caretIndex - 1).right;
    }

    private function bVisible():Boolean {
        var x:Number = caretX();
        return x >= b.scrollH + 2 - 0.5 && x <= b.scrollH + b.width - 2 + 0.5;
    }

    private function enterFrame(e:Event):void {
        if (b.length != bLength) {
            bLength = b.length;
            bChanges++;
            if (!bVisible()) {
                bHidden++;
            }
        }
    }

    private function keyUpB(e:KeyboardEvent):void {
        if (e.keyCode == 16 || e.keyCode == 17) {
            return;
        }
        if (e.keyCode == 36) {
            out("b typed " + b.length + " characters, caret hidden after " + bHidden + " of them");
        }
        out("b " + keyName(e) + ": caret=" + b.caretIndex + " visible=" + bVisible() + " scrolled=" + (b.scrollH > 0));
    }
}
}
