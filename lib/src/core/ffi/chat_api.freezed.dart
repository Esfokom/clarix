// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$NativeChatEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NativeChatEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'NativeChatEvent()';
}


}

/// @nodoc
class $NativeChatEventCopyWith<$Res>  {
$NativeChatEventCopyWith(NativeChatEvent _, $Res Function(NativeChatEvent) __);
}


/// Adds pattern-matching-related methods to [NativeChatEvent].
extension NativeChatEventPatterns on NativeChatEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NativeChatEvent_TextDelta value)?  textDelta,TResult Function( NativeChatEvent_Error value)?  error,TResult Function( NativeChatEvent_Done value)?  done,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NativeChatEvent_TextDelta() when textDelta != null:
return textDelta(_that);case NativeChatEvent_Error() when error != null:
return error(_that);case NativeChatEvent_Done() when done != null:
return done(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NativeChatEvent_TextDelta value)  textDelta,required TResult Function( NativeChatEvent_Error value)  error,required TResult Function( NativeChatEvent_Done value)  done,}){
final _that = this;
switch (_that) {
case NativeChatEvent_TextDelta():
return textDelta(_that);case NativeChatEvent_Error():
return error(_that);case NativeChatEvent_Done():
return done(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NativeChatEvent_TextDelta value)?  textDelta,TResult? Function( NativeChatEvent_Error value)?  error,TResult? Function( NativeChatEvent_Done value)?  done,}){
final _that = this;
switch (_that) {
case NativeChatEvent_TextDelta() when textDelta != null:
return textDelta(_that);case NativeChatEvent_Error() when error != null:
return error(_that);case NativeChatEvent_Done() when done != null:
return done(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text)?  textDelta,TResult Function( String message)?  error,TResult Function()?  done,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NativeChatEvent_TextDelta() when textDelta != null:
return textDelta(_that.text);case NativeChatEvent_Error() when error != null:
return error(_that.message);case NativeChatEvent_Done() when done != null:
return done();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text)  textDelta,required TResult Function( String message)  error,required TResult Function()  done,}) {final _that = this;
switch (_that) {
case NativeChatEvent_TextDelta():
return textDelta(_that.text);case NativeChatEvent_Error():
return error(_that.message);case NativeChatEvent_Done():
return done();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text)?  textDelta,TResult? Function( String message)?  error,TResult? Function()?  done,}) {final _that = this;
switch (_that) {
case NativeChatEvent_TextDelta() when textDelta != null:
return textDelta(_that.text);case NativeChatEvent_Error() when error != null:
return error(_that.message);case NativeChatEvent_Done() when done != null:
return done();case _:
  return null;

}
}

}

/// @nodoc


class NativeChatEvent_TextDelta extends NativeChatEvent {
  const NativeChatEvent_TextDelta({required this.text}): super._();
  

 final  String text;

/// Create a copy of NativeChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NativeChatEvent_TextDeltaCopyWith<NativeChatEvent_TextDelta> get copyWith => _$NativeChatEvent_TextDeltaCopyWithImpl<NativeChatEvent_TextDelta>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NativeChatEvent_TextDelta&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,text);

@override
String toString() {
  return 'NativeChatEvent.textDelta(text: $text)';
}


}

/// @nodoc
abstract mixin class $NativeChatEvent_TextDeltaCopyWith<$Res> implements $NativeChatEventCopyWith<$Res> {
  factory $NativeChatEvent_TextDeltaCopyWith(NativeChatEvent_TextDelta value, $Res Function(NativeChatEvent_TextDelta) _then) = _$NativeChatEvent_TextDeltaCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$NativeChatEvent_TextDeltaCopyWithImpl<$Res>
    implements $NativeChatEvent_TextDeltaCopyWith<$Res> {
  _$NativeChatEvent_TextDeltaCopyWithImpl(this._self, this._then);

  final NativeChatEvent_TextDelta _self;
  final $Res Function(NativeChatEvent_TextDelta) _then;

/// Create a copy of NativeChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(NativeChatEvent_TextDelta(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NativeChatEvent_Error extends NativeChatEvent {
  const NativeChatEvent_Error({required this.message}): super._();
  

 final  String message;

/// Create a copy of NativeChatEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NativeChatEvent_ErrorCopyWith<NativeChatEvent_Error> get copyWith => _$NativeChatEvent_ErrorCopyWithImpl<NativeChatEvent_Error>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NativeChatEvent_Error&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,message);

@override
String toString() {
  return 'NativeChatEvent.error(message: $message)';
}


}

/// @nodoc
abstract mixin class $NativeChatEvent_ErrorCopyWith<$Res> implements $NativeChatEventCopyWith<$Res> {
  factory $NativeChatEvent_ErrorCopyWith(NativeChatEvent_Error value, $Res Function(NativeChatEvent_Error) _then) = _$NativeChatEvent_ErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$NativeChatEvent_ErrorCopyWithImpl<$Res>
    implements $NativeChatEvent_ErrorCopyWith<$Res> {
  _$NativeChatEvent_ErrorCopyWithImpl(this._self, this._then);

  final NativeChatEvent_Error _self;
  final $Res Function(NativeChatEvent_Error) _then;

/// Create a copy of NativeChatEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(NativeChatEvent_Error(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NativeChatEvent_Done extends NativeChatEvent {
  const NativeChatEvent_Done(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NativeChatEvent_Done);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'NativeChatEvent.done()';
}


}




// dart format on
