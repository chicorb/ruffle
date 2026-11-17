//! AMF3 deserialization driven by the AVM2.
//!
//! Unlike `flash_lso`, which parses a whole value before the AVM2 sees it, this reader
//! creates AVM2 objects as it reads. This is required for `IExternalizable` classes:
//! their data has no self-describing format, so the reader must instantiate the class
//! and let its `readExternal` method consume the bytes from the same stream. Any nested
//! `readObject` call made by `readExternal` shares this reader's reference tables, as
//! in Flash Player.

use crate::avm2::array::ArrayStorage;
use crate::avm2::bytearray::{ByteArrayError, ByteArrayStorage};
use crate::avm2::error::make_error_2173;
use crate::avm2::function::FunctionArgs;
use crate::avm2::index::ArrayIndex;
use crate::avm2::object::{ArrayObject, ByteArrayObject, ClassObject, TObject as _, VectorObject};
use crate::avm2::vector::VectorStorage;
use crate::avm2::{Activation, Error, Object, Value};
use crate::string::AvmString;
use gc_arena::Collect;
use ruffle_macros::istr;
use std::rc::Rc;

/// The class information of an AMF3 object.
#[derive(Collect)]
#[collect(no_drop)]
struct Traits<'gc> {
    class_name: AvmString<'gc>,
    externalizable: bool,
    dynamic: bool,
    sealed: Vec<AvmString<'gc>>,
}

/// The reference tables of one top-level AMF3 read.
#[derive(Collect, Default)]
#[collect(no_drop)]
pub struct Amf3Tables<'gc> {
    strings: Vec<AvmString<'gc>>,
    objects: Vec<Value<'gc>>,
    traits: Vec<Rc<Traits<'gc>>>,
}

/// Read one AMF3 value from `input` at its current position, advancing it.
///
/// If this is called while `readExternal` is reading from the same `input` (that is, by
/// `input.readObject()`), the reference tables of the outer read are reused.
pub fn read_amf3_value<'gc>(
    activation: &mut Activation<'_, 'gc>,
    input: Object<'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let outer = activation.avm2().take_amf3_read_tables(input);
    let nested = outer.is_some();
    let mut tables = outer.unwrap_or_default();

    let result = Amf3Reader {
        input,
        tables: &mut tables,
    }
    .read_value(activation);

    if nested {
        activation.avm2().push_amf3_read_tables(input, tables);
    }
    result
}

struct Amf3Reader<'a, 'gc> {
    input: Object<'gc>,
    tables: &'a mut Amf3Tables<'gc>,
}

impl<'gc> Amf3Reader<'_, 'gc> {
    fn with_bytes<T>(
        &self,
        activation: &mut Activation<'_, 'gc>,
        f: impl FnOnce(&ByteArrayStorage) -> Result<T, ByteArrayError>,
    ) -> Result<T, Error<'gc>> {
        let bytearray = self
            .input
            .as_bytearray()
            .expect("AMF3 input must be a ByteArray");
        f(&bytearray).map_err(|e| e.to_avm(activation))
    }

    fn read_u8(&self, activation: &mut Activation<'_, 'gc>) -> Result<u8, Error<'gc>> {
        self.with_bytes(activation, |b| b.read_unsigned_byte())
    }

    fn read_f64(&self, activation: &mut Activation<'_, 'gc>) -> Result<f64, Error<'gc>> {
        // AMF is always big-endian, whatever the `endian` of the ByteArray.
        self.with_bytes(activation, |b| {
            let bytes = b.read_bytes(8)?;
            Ok(f64::from_be_bytes(bytes.try_into().unwrap()))
        })
    }

    fn read_raw(
        &self,
        activation: &mut Activation<'_, 'gc>,
        len: usize,
    ) -> Result<Vec<u8>, Error<'gc>> {
        self.with_bytes(activation, |b| b.read_bytes(len).map(|b| b.to_vec()))
    }

    /// A variable-length 29-bit unsigned integer.
    fn read_u29(&self, activation: &mut Activation<'_, 'gc>) -> Result<u32, Error<'gc>> {
        let mut value = 0u32;
        for _ in 0..3 {
            let byte = self.read_u8(activation)? as u32;
            value = (value << 7) | (byte & 0x7F);
            if byte & 0x80 == 0 {
                return Ok(value);
            }
        }
        let byte = self.read_u8(activation)? as u32;
        Ok((value << 8) | byte)
    }

    fn read_i29(&self, activation: &mut Activation<'_, 'gc>) -> Result<i32, Error<'gc>> {
        let value = self.read_u29(activation)?;
        Ok(((value << 3) as i32) >> 3)
    }

    fn read_string(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
    ) -> Result<AvmString<'gc>, Error<'gc>> {
        let header = self.read_u29(activation)?;
        if header & 1 == 0 {
            return self.string_ref(activation, (header >> 1) as usize);
        }
        let bytes = self.read_raw(activation, (header >> 1) as usize)?;
        if bytes.is_empty() {
            // The empty string is never sent by reference.
            return Ok(istr!(""));
        }
        let string = AvmString::new_utf8_bytes(activation.gc(), &bytes);
        self.tables.strings.push(string);
        Ok(string)
    }

    fn string_ref(
        &self,
        activation: &mut Activation<'_, 'gc>,
        index: usize,
    ) -> Result<AvmString<'gc>, Error<'gc>> {
        match self.tables.strings.get(index) {
            Some(s) => Ok(*s),
            None => Err(invalid_reference(activation)),
        }
    }

    fn object_ref(
        &self,
        activation: &mut Activation<'_, 'gc>,
        index: usize,
    ) -> Result<Value<'gc>, Error<'gc>> {
        match self.tables.objects.get(index) {
            Some(v) => Ok(*v),
            None => Err(invalid_reference(activation)),
        }
    }

    /// Reads the U29 header shared by every referenceable type. Returns either the
    /// referenced object, or the header's value (shifted) for an inline object.
    fn read_ref_or_value(
        &self,
        activation: &mut Activation<'_, 'gc>,
    ) -> Result<Result<Value<'gc>, u32>, Error<'gc>> {
        let header = self.read_u29(activation)?;
        if header & 1 == 0 {
            Ok(Ok(self.object_ref(activation, (header >> 1) as usize)?))
        } else {
            Ok(Err(header >> 1))
        }
    }

    fn read_value(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
    ) -> Result<Value<'gc>, Error<'gc>> {
        let marker = self.read_u8(activation)?;
        Ok(match marker {
            0x00 => Value::Undefined,
            0x01 => Value::Null,
            0x02 => false.into(),
            0x03 => true.into(),
            0x04 => self.read_i29(activation)?.into(),
            0x05 => self.read_f64(activation)?.into(),
            0x06 => self.read_string(activation)?.into(),
            // XMLDocument (0x07) and XML (0x0B) are both read as AS3 `XML`, as in `amf.rs`.
            0x07 | 0x0B => match self.read_ref_or_value(activation)? {
                Ok(v) => v,
                Err(len) => {
                    let bytes = self.read_raw(activation, len as usize)?;
                    let text = AvmString::new_utf8_bytes(activation.gc(), &bytes);
                    let xml = activation
                        .avm2()
                        .classes()
                        .xml
                        .construct(activation, &[text.into()])?;
                    self.tables.objects.push(xml);
                    xml
                }
            },
            0x08 => match self.read_ref_or_value(activation)? {
                Ok(v) => v,
                Err(_) => {
                    let time = self.read_f64(activation)?;
                    let date = activation
                        .avm2()
                        .classes()
                        .date
                        .construct(activation, &[time.into()])?;
                    self.tables.objects.push(date);
                    date
                }
            },
            0x09 => self.read_array(activation)?,
            0x0A => self.read_object(activation)?,
            0x0C => match self.read_ref_or_value(activation)? {
                Ok(v) => v,
                Err(len) => {
                    let bytes = self.read_raw(activation, len as usize)?;
                    let storage = ByteArrayStorage::from_vec(activation.context, bytes);
                    let bytearray: Value<'gc> =
                        ByteArrayObject::from_storage(activation.context, storage).into();
                    self.tables.objects.push(bytearray);
                    bytearray
                }
            },
            0x0D..=0x10 => self.read_vector(activation, marker)?,
            0x11 => self.read_dictionary(activation)?,
            _ => {
                tracing::error!("AMF3: unknown type marker {marker:#04x}");
                return Err(invalid_reference(activation));
            }
        })
    }

    fn read_array(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
    ) -> Result<Value<'gc>, Error<'gc>> {
        let dense_len = match self.read_ref_or_value(activation)? {
            Ok(v) => return Ok(v),
            Err(len) => len as usize,
        };

        let array = ArrayObject::from_storage(activation.context, ArrayStorage::new(0));
        self.tables.objects.push(array.into());

        // The associative portion comes first, terminated by an empty name.
        let mut assoc = Vec::new();
        loop {
            let name = self.read_string(activation)?;
            if name.is_empty() {
                break;
            }
            let value = self.read_value(activation)?;
            assoc.push((name, value));
        }

        let mut dense = Vec::with_capacity(dense_len.min(4096));
        for _ in 0..dense_len {
            dense.push(Some(self.read_value(activation)?));
        }
        array
            .storage_mut(activation.gc())
            .replace_dense_storage(dense);

        for (name, value) in assoc {
            if let Some(index) = ArrayIndex::from_wstr(&name) {
                array.set_element(activation.gc(), index, value);
            } else {
                array.set_dynamic_property(name, value, activation.gc());
            }
        }

        Ok(array.into())
    }

    fn read_traits(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
        header: u32,
    ) -> Result<Rc<Traits<'gc>>, Error<'gc>> {
        // `header` is the U29 without its "inline object" bit.
        if header & 1 == 0 {
            return match self.tables.traits.get((header >> 1) as usize) {
                Some(t) => Ok(t.clone()),
                None => Err(invalid_reference(activation)),
            };
        }

        let externalizable = header & 2 != 0;
        let dynamic = header & 4 != 0;
        let sealed_count = header >> 3;
        let class_name = self.read_string(activation)?;
        let mut sealed = Vec::new();
        if !externalizable {
            for _ in 0..sealed_count {
                sealed.push(self.read_string(activation)?);
            }
        }

        let traits = Rc::new(Traits {
            class_name,
            externalizable,
            dynamic,
            sealed,
        });
        self.tables.traits.push(traits.clone());
        Ok(traits)
    }

    fn read_object(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
    ) -> Result<Value<'gc>, Error<'gc>> {
        let header = match self.read_ref_or_value(activation)? {
            Ok(v) => return Ok(v),
            Err(header) => header,
        };
        let traits = self.read_traits(activation, header)?;

        let class = alias_to_class(activation, traits.class_name);
        let object = class.construct(activation, &[])?;
        self.tables.objects.push(object);

        if traits.externalizable {
            self.read_external(activation, class, object)?;
            return Ok(object);
        }

        for name in &traits.sealed {
            let value = self.read_value(activation)?;
            set_property(activation, object, *name, value)?;
        }

        if traits.dynamic {
            loop {
                let name = self.read_string(activation)?;
                if name.is_empty() {
                    break;
                }
                let value = self.read_value(activation)?;
                set_property(activation, object, name, value)?;
            }
        }

        Ok(object)
    }

    /// Let an `IExternalizable` object read its own data from the input.
    fn read_external(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
        class: ClassObject<'gc>,
        object: Value<'gc>,
    ) -> Result<(), Error<'gc>> {
        let iexternalizable = activation.avm2().class_defs().iexternalizable;
        let implements = object
            .as_object()
            .is_some_and(|o| o.is_of_type(iexternalizable));
        if !implements {
            return Err(make_error_2173(
                activation,
                &class
                    .inner_class_definition()
                    .name()
                    .to_qualified_name(activation.gc())
                    .to_string(),
            ));
        }

        // Hand our tables over so that `input.readObject()` can use them.
        let tables = std::mem::take(self.tables);
        activation.avm2().push_amf3_read_tables(self.input, tables);

        let result = object.call_public_property(
            AvmString::new_utf8(activation.gc(), "readExternal"),
            FunctionArgs::from_slice(&[self.input.into()]),
            activation,
        );

        *self.tables = activation
            .avm2()
            .take_amf3_read_tables(self.input)
            .expect("AMF3 read tables must still be on the stack");
        result.map(|_| ())
    }

    fn read_vector(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
        marker: u8,
    ) -> Result<Value<'gc>, Error<'gc>> {
        let len = match self.read_ref_or_value(activation)? {
            Ok(v) => return Ok(v),
            Err(len) => len as usize,
        };
        let is_fixed = self.read_u8(activation)? != 0;

        let class_defs = activation.avm2().class_defs();
        let value_type = match marker {
            0x0D => class_defs.int,
            0x0E => class_defs.uint,
            0x0F => class_defs.number,
            _ => {
                let name = self.read_string(activation)?;
                alias_to_class(activation, name).inner_class_definition()
            }
        };

        // The vector must be in the table before its items, which may reference it.
        let vector = VectorObject::from_vector(
            VectorStorage::new(0, is_fixed, Some(value_type)),
            activation,
        );
        self.tables.objects.push(vector.into());

        let mut values = Vec::with_capacity(len.min(4096));
        for _ in 0..len {
            let value: Value<'gc> = match marker {
                0x0D => self
                    .with_bytes(activation, |b| {
                        b.read_bytes(4)
                            .map(|b| i32::from_be_bytes(b.try_into().unwrap()))
                    })?
                    .into(),
                0x0E => self
                    .with_bytes(activation, |b| {
                        b.read_bytes(4)
                            .map(|b| u32::from_be_bytes(b.try_into().unwrap()))
                    })?
                    .into(),
                0x0F => self.read_f64(activation)?.into(),
                _ => match self.read_value(activation)? {
                    // There's no Vector.<void>
                    Value::Undefined => Value::Null,
                    v => v,
                },
            };
            values.push(value);
        }
        vector.storage_mut(activation.gc()).replace_storage(values);

        Ok(vector.into())
    }

    fn read_dictionary(
        &mut self,
        activation: &mut Activation<'_, 'gc>,
    ) -> Result<Value<'gc>, Error<'gc>> {
        let len = match self.read_ref_or_value(activation)? {
            Ok(v) => return Ok(v),
            Err(len) => len as usize,
        };
        let weak_keys = self.read_u8(activation)? != 0;

        let dictionary = activation
            .avm2()
            .classes()
            .dictionary
            .construct(activation, &[weak_keys.into()])?;
        self.tables.objects.push(dictionary);
        let dict_obj = dictionary
            .as_object()
            .and_then(|o| o.as_dictionary_object())
            .expect("Failed to get dictionary from constructed object");

        for _ in 0..len {
            let key = self.read_value(activation)?;
            let value = self.read_value(activation)?;
            if let Value::Object(key) = key {
                dict_obj.set_property_by_object(key, value, activation.gc());
            } else {
                let key = key.coerce_to_string(activation)?;
                dict_obj.set_dynamic_property(key, value, activation.gc());
            }
        }

        Ok(dictionary)
    }
}

fn alias_to_class<'gc>(
    activation: &mut Activation<'_, 'gc>,
    alias: AvmString<'gc>,
) -> ClassObject<'gc> {
    activation
        .avm2()
        .get_class_by_alias(alias)
        .unwrap_or_else(|| activation.avm2().classes().object)
}

fn set_property<'gc>(
    activation: &mut Activation<'_, 'gc>,
    object: Value<'gc>,
    name: AvmString<'gc>,
    value: Value<'gc>,
) -> Result<(), Error<'gc>> {
    // Flash Player logs the error and continues deserializing the rest of the object,
    // even when calling a custom setter (same as `amf.rs`).
    if let Err(e) = object.set_public_property(name, value, activation) {
        tracing::warn!("Ignoring error deserializing AMF property for field {name:?}: {e:?}");
        if let Some(e) = e.as_avm_error() {
            let stringified = e.coerce_to_string(activation)?;
            activation.context.avm_trace(&stringified.to_string());
        }
    }
    Ok(())
}

fn invalid_reference<'gc>(activation: &mut Activation<'_, 'gc>) -> Error<'gc> {
    // TODO: match the error Flash Player throws for malformed AMF3 data.
    ByteArrayError::EndOfFile.to_avm(activation)
}

/// Reads a Flash Remoting response packet, decoding each message body with the AVM2.
///
/// `on_message` is called with the target URI and body of each message, in order, as soon
/// as it is read. Bodies switched to AMF3 (the AMF0 "AVM+" marker) are read by this module,
/// so they can contain `IExternalizable` objects; other AMF0 values go through `flash_lso`.
/// Packet headers are read and ignored.
pub fn read_remoting_response<'gc>(
    activation: &mut Activation<'_, 'gc>,
    data: Vec<u8>,
    mut on_message: impl FnMut(&mut Activation<'_, 'gc>, &str, Value<'gc>),
) -> Result<(), Error<'gc>> {
    let storage = ByteArrayStorage::from_vec(activation.context, data);
    let input: Object<'gc> = ByteArrayObject::from_storage(activation.context, storage).into();
    let reader = Amf3Reader {
        input,
        tables: &mut Amf3Tables::default(),
    };

    let read_u16 = |activation: &mut Activation<'_, 'gc>| {
        reader.with_bytes(activation, |b| {
            b.read_bytes(2)
                .map(|b| u16::from_be_bytes(b.try_into().unwrap()))
        })
    };
    let read_utf = |activation: &mut Activation<'_, 'gc>| -> Result<String, Error<'gc>> {
        let len = read_u16(activation)? as usize;
        let bytes = reader.read_raw(activation, len)?;
        Ok(String::from_utf8_lossy(&bytes).into_owned())
    };
    let read_body = |activation: &mut Activation<'_, 'gc>| -> Result<Value<'gc>, Error<'gc>> {
        // The body length is often 0xFFFFFFFF (unknown), so bodies are read in sequence.
        reader.read_raw(activation, 4)?;
        read_amf0_value(activation, input)
    };

    reader.read_u8(activation)?;
    let _version = reader.read_u8(activation)?;

    let header_count = read_u16(activation)?;
    for _ in 0..header_count {
        let _name = read_utf(activation)?;
        let _must_understand = reader.read_u8(activation)?;
        read_body(activation)?;
    }

    let message_count = read_u16(activation)?;
    for _ in 0..message_count {
        let target_uri = read_utf(activation)?;
        let _response_uri = read_utf(activation)?;
        let value = read_body(activation)?;
        tracing::debug!("AMF response message {target_uri}: {value:?}");
        on_message(activation, &target_uri, value);
    }

    Ok(())
}

/// Reads an AMF0 value from `input`; an AMF0 "AVM+" marker switches to AMF3.
fn read_amf0_value<'gc>(
    activation: &mut Activation<'_, 'gc>,
    input: Object<'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let amf = {
        let bytearray = input.as_bytearray().expect("AMF input must be a ByteArray");
        let position = bytearray.position();
        if bytearray.get(position) == Some(0x11) {
            bytearray.set_position(position + 1);
            drop(bytearray);
            // Each AMF0-to-AMF3 switch starts with fresh reference tables.
            return read_amf3_value(activation, input);
        }

        let bytes = bytearray
            .read_at(bytearray.bytes_available(), position)
            .map_err(|e| e.to_avm(activation))?;
        let (rest, amf) = flash_lso::amf0::read::AMF0Decoder::default()
            .parse_single_element(bytes)
            .map_err(|_| invalid_reference(activation))?;
        let consumed = bytes.len() - rest.len();
        bytearray.set_position(position + consumed);
        amf
    };
    crate::avm2::amf::deserialize_value(activation, &amf)
}
