package {
import flash.display.Sprite;
import flash.utils.describeType;

public class Test extends Sprite {
    public function Test() {
        show("Tagged (class)", describeType(Tagged));
        show("Tagged (instance)", describeType(new Tagged()));
        show("SubTagged (class)", describeType(SubTagged));
        show("SubTagged (instance)", describeType(new SubTagged()));
        show("Plain (class)", describeType(Plain));
        show("ITagged (interface)", describeType(ITagged));

        // Libraries that read class metadata (e.g. reflection helpers) expect exactly one tag.
        var tags:XMLList = describeType(Tagged).factory.metadata.(@name == "Metadata");
        trace("factory [Metadata] tags on Tagged: " + tags.length());
        trace("instance [Metadata] tags on Tagged: " + describeType(new Tagged()).metadata.(@name == "Metadata").length());
    }

    private function show(label:String, xml:XML):void {
        trace("// " + label);
        trace(normalizeXML(xml));
    }

    // Children sorted, so the output does not depend on the order of traits.
    private function normalizeXML(data:XML, indent:uint = 0):String {
        var pad:String = "";
        for (var i:uint = 0; i < indent; i++) pad += " ";
        var output:String = pad + "<" + data.name();
        for each (var attr:XML in data.attributes()) {
            output += " " + attr.name() + "=\"" + attr + "\"";
        }
        if (data.children().length() == 0) {
            return output + "/>";
        }
        output += ">\n";
        var childStrs:Array = [];
        for each (var child:XML in data.children()) {
            childStrs.push(normalizeXML(child, indent + 2));
        }
        childStrs.sort();
        for each (var childStr:String in childStrs) {
            output += childStr + "\n";
        }
        return output + pad + "</" + data.name() + ">";
    }
}
}
