//! AMF3 serialization driven by the AVM2.
//!
//! The counterpart of `amf_read`: values are written straight from AVM2 objects, so that
//! an `IExternalizable` object can write its own data with `writeExternal`, into the same
//! output and sharing this writer's reference tables (as in Flash Player). Object
//! references are by identity, like Flash Player.

use crate::avm2::bytearray::ByteArrayStorage;
use crate::avm2::class::Class;
use crate::avm2::function::FunctionArgs;
use crate::avm2::object::{ByteArrayObject, TObject as _};
use crate::avm2::property::Property;
use crate::avm2::{Activation, Error, Object, Value};
use crate::string::AvmString;
use fnv::FnvHashMap;
use gc_arena::Collect;

/// The reference tables of one top-level AMF3 write.
#[derive(Collect, Default)]
#[collect(no_drop)]
pub struct Amf3WriteTables<'gc> {
    strings: FnvHashMap<AvmString<'gc>, u32>,
    objects: FnvHashMap<Object<'gc>, u32>,
    traits: FnvHashMap<Class<'gc>, u32>,
}

/// Write one AMF3 value to `output` (a `ByteArray`) at its current position.
///
/// If this is called while `writeExternal` is writing to the same `output` (that is, by
/// `output.writeObject()`), the reference tables of the outer write are reused.
pub fn write_amf3_value<'gc>(
    activation: &mut Activation<'_, 'gc>,
    output: Object<'gc>,
    value: Value<'gc>,
) -> Result<(), Error<'gc>> {
    let outer = activation.avm2().take_amf3_write_tables(output);
    let nested = outer.is_some();
    let mut tables = outer.unwrap_or_default();

    let result = Amf3Writer {
        output,
        tables: &mut tables,
    }
    .write_value(activation, value);

    if nested {
        activation.avm2().push_amf3_write_tables(output, tables);
    }
    result
}

/// Serialize one value to standalone AMF3 bytes, with fresh reference tables.
pub fn amf3_bytes<'gc>(
    activation: &mut Activation<'_, 'gc>,
    value: Value<'gc>,
) -> Result<Vec<u8>, Error<'gc>> {
    let storage = ByteArrayStorage::new(activation.context);
    let output: Object<'gc> = ByteArrayObject::from_storage(activation.context, storage).into();
    write_amf3_value(activation, output, value)?;
    let bytes = output
        .as_bytearray()
        .expect("AMF3 output must be a ByteArray")
        .bytes()
        .to_vec();
    Ok(bytes)
}

struct Amf3Writer<'a, 'gc> {
    output: Object<'gc>,
    tables: &'a mut Amf3WriteTables<'gc>,
}

impl<'gc> Amf3Writer<'_, 'gc> {
    fn write_raw(
        &self,
        activation: &mut Activation<'_, 'gc>,
        bytes: &[u8],
    ) -> Result<(), Error<'gc>> {
        let result = self
            .output
            .as_bytearray_mut()
            .expect("AMF3 output must be a ByteArray")
            .write_bytes(bytes);
        result.map_err(|e| e.to_avm(activation))
    }

    /// A variable-length 29-bit unsigned integer.
    fn write_u29(&self, activation: &mut Activation<'_, 'gc>, n: u32) -> Result<(), Error<'gc>> {
        let n = n & 0x1FFF_FFFF;
        let bytes: &[u8] = if n < 0x80 {
            &[n as u8]
        } else if n < 0x4000 {
            &[(n >> 7) as u8 | 0x80, (n & 0x7F) as u8]
        } else if n < 0x20_0000 {
            &[
                (n >> 14) as u8 | 0x80,
                (n >> 7) as u8 | 0x80,
                (n & 0x7F) as u8,
            ]
        } else {
            &[
                (n >> 22) as u8 | 0x80,
                (n >> 15) as u8 | 0x80,
                (n >> 8) as u8 | 0x80,
                n as u8,
            ]
        };
        self.write_raw(activation, bytes)
    }

    fn write_string(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
        s: AvmString<'gc>,
    ) -> Result<(), Error<'gc>> {
        if s.is_empty() {
            // The empty string is never sent by reference.
            return self.write_u29(activation, 1);
        }
        if let Some(index) = self.tables.strings.get(&s) {
            return self.write_u29(activation, index << 1);
        }
        let index = self.tables.strings.len() as u32;
        self.tables.strings.insert(s, index);
        let utf8 = s.to_utf8_lossy();
        self.write_u29(activation, ((utf8.len() as u32) << 1) | 1)?;
        self.write_raw(activation, utf8.as_bytes())
    }

    fn write_f64(&self, activation: &mut Activation<'_, 'gc>, n: f64) -> Result<(), Error<'gc>> {
        self.write_raw(activation, &n.to_be_bytes())
    }

    fn write_value(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
        value: Value<'gc>,
    ) -> Result<(), Error<'gc>> {
        match value.normalize() {
            Value::Undefined => self.write_raw(activation, &[0x00]),
            Value::Null => self.write_raw(activation, &[0x01]),
            Value::Bool(false) => self.write_raw(activation, &[0x02]),
            Value::Bool(true) => self.write_raw(activation, &[0x03]),
            Value::Integer(i) if (-0x1000_0000..0x1000_0000).contains(&i) => {
                self.write_raw(activation, &[0x04])?;
                self.write_u29(activation, i as u32)
            }
            Value::Integer(i) => {
                self.write_raw(activation, &[0x05])?;
                self.write_f64(activation, i as f64)
            }
            Value::Number(n) => {
                self.write_raw(activation, &[0x05])?;
                self.write_f64(activation, n)
            }
            Value::String(s) => {
                self.write_raw(activation, &[0x06])?;
                self.write_string(activation, s)
            }
            Value::Object(o) => self.write_object(activation, o),
        }
    }

    fn write_object(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
        o: Object<'gc>,
    ) -> Result<(), Error<'gc>> {
        // Functions and display objects are written as `undefined`, as in `amf.rs`.
        if o.as_function_object().is_some() || o.as_display_object().is_some() {
            return self.write_raw(activation, &[0x00]);
        }

        let marker = if o.as_array_storage().is_some() {
            0x09
        } else if let Some(vector) = o.as_vector_storage() {
            let class_defs = activation.avm2().class_defs();
            match vector.value_type() {
                Some(t) if t == class_defs.int => 0x0D,
                Some(t) if t == class_defs.uint => 0x0E,
                Some(t) if t == class_defs.number => 0x0F,
                _ => 0x10,
            }
        } else if o.as_date_object().is_some() {
            0x08
        } else if o.as_xml_object().is_some() {
            0x0B
        } else if o.as_bytearray().is_some() {
            0x0C
        } else if o.as_dictionary_object().is_some() {
            0x11
        } else {
            0x0A
        };
        self.write_raw(activation, &[marker])?;

        if let Some(index) = self.tables.objects.get(&o) {
            return self.write_u29(activation, index << 1);
        }
        let index = self.tables.objects.len() as u32;
        self.tables.objects.insert(o, index);

        match marker {
            0x09 => self.write_array(activation, o),
            0x0D..=0x10 => self.write_vector(activation, o, marker),
            0x08 => {
                let date = o.as_date_object().unwrap();
                let time = date
                    .date_time()
                    .map(|date_time| date_time.timestamp_millis() as f64)
                    // "Invalid Date" is serialized as a NaN
                    .unwrap_or(f64::NAN);
                self.write_u29(activation, 1)?;
                self.write_f64(activation, time)
            }
            0x0B => {
                let xml = o.as_xml_object().unwrap();
                let text = xml
                    .node()
                    .xml_to_xml_string(activation)
                    .to_utf8_lossy()
                    .into_owned();
                self.write_u29(activation, ((text.len() as u32) << 1) | 1)?;
                self.write_raw(activation, text.as_bytes())
            }
            0x0C => {
                let bytes = o.as_bytearray().unwrap().bytes().to_vec();
                self.write_u29(activation, ((bytes.len() as u32) << 1) | 1)?;
                self.write_raw(activation, &bytes)
            }
            0x11 => self.write_dictionary(activation, o),
            _ => self.write_typed_object(activation, o),
        }
    }

    /// The enumerable properties of `o`, skipping functions (as `amf.rs` does).
    fn enumerants(
        activation: &mut Activation<'_, 'gc>,
        o: Object<'gc>,
    ) -> Result<Vec<(AvmString<'gc>, Value<'gc>)>, Error<'gc>> {
        let mut out = Vec::new();
        let mut index = o.get_next_enumerant(0, activation)?;
        while index != 0 {
            let name = o
                .get_enumerant_name(index, activation)?
                .coerce_to_string(activation)?;
            let value = o.get_enumerant_value(index, activation)?;
            if value
                .as_object()
                .and_then(|v| v.as_function_object())
                .is_none()
            {
                out.push((name, value));
            }
            index = o.get_next_enumerant(index, activation)?;
        }
        Ok(out)
    }

    fn write_array(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
        o: Object<'gc>,
    ) -> Result<(), Error<'gc>> {
        // Elements named after their position form the dense portion; everything else
        // (non-index properties, and elements after a hole) is associative, as in `amf.rs`.
        let mut dense = Vec::new();
        let mut assoc = Vec::new();
        for (name, value) in Self::enumerants(activation, o)? {
            if assoc.is_empty() && name.to_string() == dense.len().to_string() {
                dense.push(value);
            } else {
                assoc.push((name, value));
            }
        }

        self.write_u29(activation, ((dense.len() as u32) << 1) | 1)?;
        for (name, value) in assoc {
            self.write_string(activation, name)?;
            self.write_value(activation, value)?;
        }
        self.write_u29(activation, 1)?; // empty string: end of the associative portion
        for value in dense {
            self.write_value(activation, value)?;
        }
        Ok(())
    }

    fn write_vector(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
        o: Object<'gc>,
        marker: u8,
    ) -> Result<(), Error<'gc>> {
        let (values, is_fixed, value_type): (Vec<Value<'gc>>, bool, Option<Class<'gc>>) = {
            let vector = o.as_vector_storage().unwrap();
            (
                vector.iter().collect(),
                vector.is_fixed(),
                vector.value_type(),
            )
        };

        self.write_u29(activation, ((values.len() as u32) << 1) | 1)?;
        self.write_raw(activation, &[is_fixed as u8])?;
        match marker {
            0x0D => {
                for v in values {
                    self.write_raw(activation, &v.as_i32().to_be_bytes())?;
                }
            }
            0x0E => {
                for v in values {
                    self.write_raw(activation, &v.as_u32().to_be_bytes())?;
                }
            }
            0x0F => {
                for v in values {
                    self.write_f64(activation, v.as_f64())?;
                }
            }
            _ => {
                let value_type =
                    value_type.unwrap_or_else(|| activation.avm2().class_defs().object);
                match activation.avm2().get_alias_by_class(value_type) {
                    Some(name) => self.write_string(activation, name)?,
                    None => self.write_u29(activation, 1)?,
                }
                for v in values {
                    self.write_value(activation, v)?;
                }
            }
        }
        Ok(())
    }

    fn write_dictionary(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
        o: Object<'gc>,
    ) -> Result<(), Error<'gc>> {
        let dictionary = o.as_dictionary_object().unwrap();
        let mut entries = Vec::new();
        let mut index = dictionary.get_next_enumerant(0, activation)?;
        while index != 0 {
            let key = dictionary.get_enumerant_name(index, activation)?;
            let value = dictionary.get_enumerant_value(index, activation)?;
            entries.push((key, value));
            index = dictionary.get_next_enumerant(index, activation)?;
        }

        self.write_u29(activation, ((entries.len() as u32) << 1) | 1)?;
        // FIXME change this once weak keys are implemented (same as `amf.rs`)
        self.write_raw(activation, &[0x00])?;
        for (key, value) in entries {
            self.write_value(activation, key)?;
            self.write_value(activation, value)?;
        }
        Ok(())
    }

    /// The sealed members written for an instance: public read-write properties, sorted by
    /// name to match `amf.rs` (Flash Player uses declaration order).
    fn sealed_members(o: Object<'gc>) -> Vec<AvmString<'gc>> {
        let mut props = o
            .vtable()
            .public_properties()
            .filter(|(_, prop)| match prop {
                Property::Method { .. } => false,
                Property::Virtual { get, set } => get.is_some() && set.is_some(),
                _ => true,
            })
            .map(|(name, _)| name)
            .collect::<Vec<_>>();
        props.sort();
        props
    }

    fn write_typed_object(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
        o: Object<'gc>,
    ) -> Result<(), Error<'gc>> {
        let class = o.instance_class();
        let externalizable = o.is_of_type(activation.avm2().class_defs().iexternalizable);
        let dynamic = !class.is_sealed();
        let sealed = if externalizable {
            Vec::new()
        } else {
            Self::sealed_members(o)
        };

        if let Some(index) = self.tables.traits.get(&class) {
            self.write_u29(activation, (index << 2) | 0b01)?;
        } else {
            let index = self.tables.traits.len() as u32;
            self.tables.traits.insert(class, index);
            let header = if externalizable {
                0b0111
            } else {
                ((sealed.len() as u32) << 4) | ((dynamic as u32) << 3) | 0b0011
            };
            self.write_u29(activation, header)?;
            match activation.avm2().get_alias_by_class(class) {
                Some(alias) => self.write_string(activation, alias)?,
                None => self.write_u29(activation, 1)?,
            }
            for name in &sealed {
                self.write_string(activation, *name)?;
            }
        }

        if externalizable {
            return self.write_external(activation, o);
        }

        for name in sealed {
            let value = Value::from(o).get_public_property(name, activation)?;
            self.write_value(activation, value)?;
        }
        if dynamic {
            for (name, value) in Self::enumerants(activation, o)? {
                self.write_string(activation, name)?;
                self.write_value(activation, value)?;
            }
            self.write_u29(activation, 1)?; // empty string: end of the associative portion
        }
        Ok(())
    }

    /// Let an `IExternalizable` object write its own data to the output.
    fn write_external(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
        o: Object<'gc>,
    ) -> Result<(), Error<'gc>> {
        // Hand our tables over so that `output.writeObject()` can use them.
        let tables = std::mem::take(self.tables);
        activation
            .avm2()
            .push_amf3_write_tables(self.output, tables);

        let result = Value::from(o).call_public_property(
            AvmString::new_utf8(activation.gc(), "writeExternal"),
            FunctionArgs::from_slice(&[self.output.into()]),
            activation,
        );

        *self.tables = activation
            .avm2()
            .take_amf3_write_tables(self.output)
            .expect("AMF3 write tables must still be on the stack");
        result.map(|_| ())
    }
}
