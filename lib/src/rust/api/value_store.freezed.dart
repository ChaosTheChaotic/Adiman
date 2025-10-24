// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'value_store.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$CurrentSongUpdate {
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is CurrentSongUpdate);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'CurrentSongUpdate()';
  }
}

/// @nodoc
class $CurrentSongUpdateCopyWith<$Res> {
  $CurrentSongUpdateCopyWith(
      CurrentSongUpdate _, $Res Function(CurrentSongUpdate) __);
}

/// Adds pattern-matching-related methods to [CurrentSongUpdate].
extension CurrentSongUpdatePatterns on CurrentSongUpdate {
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
    TResult Function(CurrentSongUpdate_NoChange value)? noChange,
    TResult Function(CurrentSongUpdate_SetToNone value)? setToNone,
    TResult Function(CurrentSongUpdate_SetToSome value)? setToSome,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case CurrentSongUpdate_NoChange() when noChange != null:
        return noChange(_that);
      case CurrentSongUpdate_SetToNone() when setToNone != null:
        return setToNone(_that);
      case CurrentSongUpdate_SetToSome() when setToSome != null:
        return setToSome(_that);
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
    required TResult Function(CurrentSongUpdate_NoChange value) noChange,
    required TResult Function(CurrentSongUpdate_SetToNone value) setToNone,
    required TResult Function(CurrentSongUpdate_SetToSome value) setToSome,
  }) {
    final _that = this;
    switch (_that) {
      case CurrentSongUpdate_NoChange():
        return noChange(_that);
      case CurrentSongUpdate_SetToNone():
        return setToNone(_that);
      case CurrentSongUpdate_SetToSome():
        return setToSome(_that);
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
    TResult? Function(CurrentSongUpdate_NoChange value)? noChange,
    TResult? Function(CurrentSongUpdate_SetToNone value)? setToNone,
    TResult? Function(CurrentSongUpdate_SetToSome value)? setToSome,
  }) {
    final _that = this;
    switch (_that) {
      case CurrentSongUpdate_NoChange() when noChange != null:
        return noChange(_that);
      case CurrentSongUpdate_SetToNone() when setToNone != null:
        return setToNone(_that);
      case CurrentSongUpdate_SetToSome() when setToSome != null:
        return setToSome(_that);
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
    TResult Function()? noChange,
    TResult Function()? setToNone,
    TResult Function(SongMetadata field0)? setToSome,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case CurrentSongUpdate_NoChange() when noChange != null:
        return noChange();
      case CurrentSongUpdate_SetToNone() when setToNone != null:
        return setToNone();
      case CurrentSongUpdate_SetToSome() when setToSome != null:
        return setToSome(_that.field0);
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
    required TResult Function() noChange,
    required TResult Function() setToNone,
    required TResult Function(SongMetadata field0) setToSome,
  }) {
    final _that = this;
    switch (_that) {
      case CurrentSongUpdate_NoChange():
        return noChange();
      case CurrentSongUpdate_SetToNone():
        return setToNone();
      case CurrentSongUpdate_SetToSome():
        return setToSome(_that.field0);
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
    TResult? Function()? noChange,
    TResult? Function()? setToNone,
    TResult? Function(SongMetadata field0)? setToSome,
  }) {
    final _that = this;
    switch (_that) {
      case CurrentSongUpdate_NoChange() when noChange != null:
        return noChange();
      case CurrentSongUpdate_SetToNone() when setToNone != null:
        return setToNone();
      case CurrentSongUpdate_SetToSome() when setToSome != null:
        return setToSome(_that.field0);
      case _:
        return null;
    }
  }
}

/// @nodoc

class CurrentSongUpdate_NoChange extends CurrentSongUpdate {
  const CurrentSongUpdate_NoChange() : super._();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CurrentSongUpdate_NoChange);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'CurrentSongUpdate.noChange()';
  }
}

/// @nodoc

class CurrentSongUpdate_SetToNone extends CurrentSongUpdate {
  const CurrentSongUpdate_SetToNone() : super._();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CurrentSongUpdate_SetToNone);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'CurrentSongUpdate.setToNone()';
  }
}

/// @nodoc

class CurrentSongUpdate_SetToSome extends CurrentSongUpdate {
  const CurrentSongUpdate_SetToSome(this.field0) : super._();

  final SongMetadata field0;

  /// Create a copy of CurrentSongUpdate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $CurrentSongUpdate_SetToSomeCopyWith<CurrentSongUpdate_SetToSome>
      get copyWith => _$CurrentSongUpdate_SetToSomeCopyWithImpl<
          CurrentSongUpdate_SetToSome>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is CurrentSongUpdate_SetToSome &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'CurrentSongUpdate.setToSome(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $CurrentSongUpdate_SetToSomeCopyWith<$Res>
    implements $CurrentSongUpdateCopyWith<$Res> {
  factory $CurrentSongUpdate_SetToSomeCopyWith(
          CurrentSongUpdate_SetToSome value,
          $Res Function(CurrentSongUpdate_SetToSome) _then) =
      _$CurrentSongUpdate_SetToSomeCopyWithImpl;
  @useResult
  $Res call({SongMetadata field0});
}

/// @nodoc
class _$CurrentSongUpdate_SetToSomeCopyWithImpl<$Res>
    implements $CurrentSongUpdate_SetToSomeCopyWith<$Res> {
  _$CurrentSongUpdate_SetToSomeCopyWithImpl(this._self, this._then);

  final CurrentSongUpdate_SetToSome _self;
  final $Res Function(CurrentSongUpdate_SetToSome) _then;

  /// Create a copy of CurrentSongUpdate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(CurrentSongUpdate_SetToSome(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as SongMetadata,
    ));
  }
}

// dart format on
