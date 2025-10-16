// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'plugin_man.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ConfigTypes {
  Object get field0;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ConfigTypes &&
            const DeepCollectionEquality().equals(other.field0, field0));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(field0));

  @override
  String toString() {
    return 'ConfigTypes(field0: $field0)';
  }
}

/// @nodoc
class $ConfigTypesCopyWith<$Res> {
  $ConfigTypesCopyWith(ConfigTypes _, $Res Function(ConfigTypes) __);
}

/// Adds pattern-matching-related methods to [ConfigTypes].
extension ConfigTypesPatterns on ConfigTypes {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(ConfigTypes_String value)? string,
    TResult Function(ConfigTypes_Bool value)? bool,
    TResult Function(ConfigTypes_Int value)? int,
    TResult Function(ConfigTypes_UInt value)? uInt,
    TResult Function(ConfigTypes_BigInt value)? bigInt,
    TResult Function(ConfigTypes_BigUInt value)? bigUInt,
    TResult Function(ConfigTypes_Float value)? float,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case ConfigTypes_String() when string != null:
        return string(_that);
      case ConfigTypes_Bool() when bool != null:
        return bool(_that);
      case ConfigTypes_Int() when int != null:
        return int(_that);
      case ConfigTypes_UInt() when uInt != null:
        return uInt(_that);
      case ConfigTypes_BigInt() when bigInt != null:
        return bigInt(_that);
      case ConfigTypes_BigUInt() when bigUInt != null:
        return bigUInt(_that);
      case ConfigTypes_Float() when float != null:
        return float(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(ConfigTypes_String value) string,
    required TResult Function(ConfigTypes_Bool value) bool,
    required TResult Function(ConfigTypes_Int value) int,
    required TResult Function(ConfigTypes_UInt value) uInt,
    required TResult Function(ConfigTypes_BigInt value) bigInt,
    required TResult Function(ConfigTypes_BigUInt value) bigUInt,
    required TResult Function(ConfigTypes_Float value) float,
  }) {
    final _that = this;
    switch (_that) {
      case ConfigTypes_String():
        return string(_that);
      case ConfigTypes_Bool():
        return bool(_that);
      case ConfigTypes_Int():
        return int(_that);
      case ConfigTypes_UInt():
        return uInt(_that);
      case ConfigTypes_BigInt():
        return bigInt(_that);
      case ConfigTypes_BigUInt():
        return bigUInt(_that);
      case ConfigTypes_Float():
        return float(_that);
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(ConfigTypes_String value)? string,
    TResult? Function(ConfigTypes_Bool value)? bool,
    TResult? Function(ConfigTypes_Int value)? int,
    TResult? Function(ConfigTypes_UInt value)? uInt,
    TResult? Function(ConfigTypes_BigInt value)? bigInt,
    TResult? Function(ConfigTypes_BigUInt value)? bigUInt,
    TResult? Function(ConfigTypes_Float value)? float,
  }) {
    final _that = this;
    switch (_that) {
      case ConfigTypes_String() when string != null:
        return string(_that);
      case ConfigTypes_Bool() when bool != null:
        return bool(_that);
      case ConfigTypes_Int() when int != null:
        return int(_that);
      case ConfigTypes_UInt() when uInt != null:
        return uInt(_that);
      case ConfigTypes_BigInt() when bigInt != null:
        return bigInt(_that);
      case ConfigTypes_BigUInt() when bigUInt != null:
        return bigUInt(_that);
      case ConfigTypes_Float() when float != null:
        return float(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? string,
    TResult Function(bool field0)? bool,
    TResult Function(int field0)? int,
    TResult Function(int field0)? uInt,
    TResult Function(BigInt field0)? bigInt,
    TResult Function(BigInt field0)? bigUInt,
    TResult Function(double field0)? float,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case ConfigTypes_String() when string != null:
        return string(_that.field0);
      case ConfigTypes_Bool() when bool != null:
        return bool(_that.field0);
      case ConfigTypes_Int() when int != null:
        return int(_that.field0);
      case ConfigTypes_UInt() when uInt != null:
        return uInt(_that.field0);
      case ConfigTypes_BigInt() when bigInt != null:
        return bigInt(_that.field0);
      case ConfigTypes_BigUInt() when bigUInt != null:
        return bigUInt(_that.field0);
      case ConfigTypes_Float() when float != null:
        return float(_that.field0);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) string,
    required TResult Function(bool field0) bool,
    required TResult Function(int field0) int,
    required TResult Function(int field0) uInt,
    required TResult Function(BigInt field0) bigInt,
    required TResult Function(BigInt field0) bigUInt,
    required TResult Function(double field0) float,
  }) {
    final _that = this;
    switch (_that) {
      case ConfigTypes_String():
        return string(_that.field0);
      case ConfigTypes_Bool():
        return bool(_that.field0);
      case ConfigTypes_Int():
        return int(_that.field0);
      case ConfigTypes_UInt():
        return uInt(_that.field0);
      case ConfigTypes_BigInt():
        return bigInt(_that.field0);
      case ConfigTypes_BigUInt():
        return bigUInt(_that.field0);
      case ConfigTypes_Float():
        return float(_that.field0);
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? string,
    TResult? Function(bool field0)? bool,
    TResult? Function(int field0)? int,
    TResult? Function(int field0)? uInt,
    TResult? Function(BigInt field0)? bigInt,
    TResult? Function(BigInt field0)? bigUInt,
    TResult? Function(double field0)? float,
  }) {
    final _that = this;
    switch (_that) {
      case ConfigTypes_String() when string != null:
        return string(_that.field0);
      case ConfigTypes_Bool() when bool != null:
        return bool(_that.field0);
      case ConfigTypes_Int() when int != null:
        return int(_that.field0);
      case ConfigTypes_UInt() when uInt != null:
        return uInt(_that.field0);
      case ConfigTypes_BigInt() when bigInt != null:
        return bigInt(_that.field0);
      case ConfigTypes_BigUInt() when bigUInt != null:
        return bigUInt(_that.field0);
      case ConfigTypes_Float() when float != null:
        return float(_that.field0);
      case _:
        return null;
    }
  }
}

/// @nodoc

class ConfigTypes_String extends ConfigTypes {
  const ConfigTypes_String(this.field0) : super._();

  @override
  final String field0;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ConfigTypes_StringCopyWith<ConfigTypes_String> get copyWith =>
      _$ConfigTypes_StringCopyWithImpl<ConfigTypes_String>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ConfigTypes_String &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'ConfigTypes.string(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $ConfigTypes_StringCopyWith<$Res>
    implements $ConfigTypesCopyWith<$Res> {
  factory $ConfigTypes_StringCopyWith(
          ConfigTypes_String value, $Res Function(ConfigTypes_String) _then) =
      _$ConfigTypes_StringCopyWithImpl;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class _$ConfigTypes_StringCopyWithImpl<$Res>
    implements $ConfigTypes_StringCopyWith<$Res> {
  _$ConfigTypes_StringCopyWithImpl(this._self, this._then);

  final ConfigTypes_String _self;
  final $Res Function(ConfigTypes_String) _then;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(ConfigTypes_String(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class ConfigTypes_Bool extends ConfigTypes {
  const ConfigTypes_Bool(this.field0) : super._();

  @override
  final bool field0;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ConfigTypes_BoolCopyWith<ConfigTypes_Bool> get copyWith =>
      _$ConfigTypes_BoolCopyWithImpl<ConfigTypes_Bool>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ConfigTypes_Bool &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'ConfigTypes.bool(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $ConfigTypes_BoolCopyWith<$Res>
    implements $ConfigTypesCopyWith<$Res> {
  factory $ConfigTypes_BoolCopyWith(
          ConfigTypes_Bool value, $Res Function(ConfigTypes_Bool) _then) =
      _$ConfigTypes_BoolCopyWithImpl;
  @useResult
  $Res call({bool field0});
}

/// @nodoc
class _$ConfigTypes_BoolCopyWithImpl<$Res>
    implements $ConfigTypes_BoolCopyWith<$Res> {
  _$ConfigTypes_BoolCopyWithImpl(this._self, this._then);

  final ConfigTypes_Bool _self;
  final $Res Function(ConfigTypes_Bool) _then;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(ConfigTypes_Bool(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc

class ConfigTypes_Int extends ConfigTypes {
  const ConfigTypes_Int(this.field0) : super._();

  @override
  final int field0;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ConfigTypes_IntCopyWith<ConfigTypes_Int> get copyWith =>
      _$ConfigTypes_IntCopyWithImpl<ConfigTypes_Int>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ConfigTypes_Int &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'ConfigTypes.int(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $ConfigTypes_IntCopyWith<$Res>
    implements $ConfigTypesCopyWith<$Res> {
  factory $ConfigTypes_IntCopyWith(
          ConfigTypes_Int value, $Res Function(ConfigTypes_Int) _then) =
      _$ConfigTypes_IntCopyWithImpl;
  @useResult
  $Res call({int field0});
}

/// @nodoc
class _$ConfigTypes_IntCopyWithImpl<$Res>
    implements $ConfigTypes_IntCopyWith<$Res> {
  _$ConfigTypes_IntCopyWithImpl(this._self, this._then);

  final ConfigTypes_Int _self;
  final $Res Function(ConfigTypes_Int) _then;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(ConfigTypes_Int(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class ConfigTypes_UInt extends ConfigTypes {
  const ConfigTypes_UInt(this.field0) : super._();

  @override
  final int field0;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ConfigTypes_UIntCopyWith<ConfigTypes_UInt> get copyWith =>
      _$ConfigTypes_UIntCopyWithImpl<ConfigTypes_UInt>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ConfigTypes_UInt &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'ConfigTypes.uInt(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $ConfigTypes_UIntCopyWith<$Res>
    implements $ConfigTypesCopyWith<$Res> {
  factory $ConfigTypes_UIntCopyWith(
          ConfigTypes_UInt value, $Res Function(ConfigTypes_UInt) _then) =
      _$ConfigTypes_UIntCopyWithImpl;
  @useResult
  $Res call({int field0});
}

/// @nodoc
class _$ConfigTypes_UIntCopyWithImpl<$Res>
    implements $ConfigTypes_UIntCopyWith<$Res> {
  _$ConfigTypes_UIntCopyWithImpl(this._self, this._then);

  final ConfigTypes_UInt _self;
  final $Res Function(ConfigTypes_UInt) _then;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(ConfigTypes_UInt(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class ConfigTypes_BigInt extends ConfigTypes {
  const ConfigTypes_BigInt(this.field0) : super._();

  @override
  final BigInt field0;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ConfigTypes_BigIntCopyWith<ConfigTypes_BigInt> get copyWith =>
      _$ConfigTypes_BigIntCopyWithImpl<ConfigTypes_BigInt>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ConfigTypes_BigInt &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'ConfigTypes.bigInt(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $ConfigTypes_BigIntCopyWith<$Res>
    implements $ConfigTypesCopyWith<$Res> {
  factory $ConfigTypes_BigIntCopyWith(
          ConfigTypes_BigInt value, $Res Function(ConfigTypes_BigInt) _then) =
      _$ConfigTypes_BigIntCopyWithImpl;
  @useResult
  $Res call({BigInt field0});
}

/// @nodoc
class _$ConfigTypes_BigIntCopyWithImpl<$Res>
    implements $ConfigTypes_BigIntCopyWith<$Res> {
  _$ConfigTypes_BigIntCopyWithImpl(this._self, this._then);

  final ConfigTypes_BigInt _self;
  final $Res Function(ConfigTypes_BigInt) _then;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(ConfigTypes_BigInt(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as BigInt,
    ));
  }
}

/// @nodoc

class ConfigTypes_BigUInt extends ConfigTypes {
  const ConfigTypes_BigUInt(this.field0) : super._();

  @override
  final BigInt field0;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ConfigTypes_BigUIntCopyWith<ConfigTypes_BigUInt> get copyWith =>
      _$ConfigTypes_BigUIntCopyWithImpl<ConfigTypes_BigUInt>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ConfigTypes_BigUInt &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'ConfigTypes.bigUInt(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $ConfigTypes_BigUIntCopyWith<$Res>
    implements $ConfigTypesCopyWith<$Res> {
  factory $ConfigTypes_BigUIntCopyWith(
          ConfigTypes_BigUInt value, $Res Function(ConfigTypes_BigUInt) _then) =
      _$ConfigTypes_BigUIntCopyWithImpl;
  @useResult
  $Res call({BigInt field0});
}

/// @nodoc
class _$ConfigTypes_BigUIntCopyWithImpl<$Res>
    implements $ConfigTypes_BigUIntCopyWith<$Res> {
  _$ConfigTypes_BigUIntCopyWithImpl(this._self, this._then);

  final ConfigTypes_BigUInt _self;
  final $Res Function(ConfigTypes_BigUInt) _then;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(ConfigTypes_BigUInt(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as BigInt,
    ));
  }
}

/// @nodoc

class ConfigTypes_Float extends ConfigTypes {
  const ConfigTypes_Float(this.field0) : super._();

  @override
  final double field0;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $ConfigTypes_FloatCopyWith<ConfigTypes_Float> get copyWith =>
      _$ConfigTypes_FloatCopyWithImpl<ConfigTypes_Float>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is ConfigTypes_Float &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'ConfigTypes.float(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $ConfigTypes_FloatCopyWith<$Res>
    implements $ConfigTypesCopyWith<$Res> {
  factory $ConfigTypes_FloatCopyWith(
          ConfigTypes_Float value, $Res Function(ConfigTypes_Float) _then) =
      _$ConfigTypes_FloatCopyWithImpl;
  @useResult
  $Res call({double field0});
}

/// @nodoc
class _$ConfigTypes_FloatCopyWithImpl<$Res>
    implements $ConfigTypes_FloatCopyWith<$Res> {
  _$ConfigTypes_FloatCopyWithImpl(this._self, this._then);

  final ConfigTypes_Float _self;
  final $Res Function(ConfigTypes_Float) _then;

  /// Create a copy of ConfigTypes
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(ConfigTypes_Float(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

// dart format on
