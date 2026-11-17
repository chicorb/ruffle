package {
import flash.display.Sprite;
import flash.events.KeyboardEvent;
import flash.events.MouseEvent;
import flash.external.ExternalInterface;
import flash.text.TextField;
import flash.text.TextFieldType;
import flash.text.TextFormat;

// Home, End, Ctrl+Home and Ctrl+End when text is selected: the caret moves from where it is
// (the end of the selection being extended), not to the start or end of the selection.
// The arrow keys, on the other hand, collapse the selection.
public class Test extends Sprite {
    private var tf:TextField;
    private var keys:Array = ["Shift+End", "Home", "Shift+End", "End", "Shift+Home", "End", "Shift+Home",
        "Ctrl+End", "Shift+Left", "Shift+Left", "Ctrl+Home", "Shift+Right",
        "Shift+Right", "Left", "Shift+Right", "Right"];
    private var step:int = 0;

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

    private function setUp():void {
        tf.text = "line one\rline two\rline three";
        tf.setSelection(12, 12);
    }

    private function out(s:String):void {
        trace(s);
        if (ExternalInterface.available) {
            ExternalInterface.call("__out", s);
        }
    }

    private function keyUp(e:KeyboardEvent):void {
        if (e.keyCode == 16 || e.keyCode == 17 || step >= keys.length) {
            return;
        }
        out(keys[step] + ": caret=" + tf.caretIndex + " sel=" + tf.selectionBeginIndex + "-" + tf.selectionEndIndex);
        step++;
    }
}
}
