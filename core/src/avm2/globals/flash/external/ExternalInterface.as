package flash.external {
    import __ruffle__.stub_setter;

    [Ruffle(Abstract)]
    public final class ExternalInterface {
        private static var _marshallExceptions:Boolean = false;

        public static native function get available():Boolean;

        public static native function addCallback(functionName:String, closure:Function):void;

        public static native function call(functionName:String, ...arguments):*;

        public static native function get objectID():String;

        public static function get marshallExceptions():Boolean {
            return _marshallExceptions;
        }

        public static function set marshallExceptions(value:Boolean):void {
            if (value) {
                // Exceptions are not passed between ActionScript and JavaScript yet:
                // Ruffle always behaves as if this were false.
                stub_setter("flash.external.ExternalInterface", "marshallExceptions");
            }
            _marshallExceptions = value;
        }
    }
}
