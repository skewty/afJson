
** (Service) - 
** Converts Fantom objects to and from their JSON representation.
@Js const mixin JsonConverters {

	** Returns a new 'JsonConverters' instance.
	** 
	** If 'converters' is 'null' then 'defConvs' is used. Common option defaults are:
	** 
	**   afFom.makeEntity : |Type objType, Field:Obj? fieldVals->Obj?| { ...use Type.make()...  }
	**   afFom.strictMode : false
	** 
	** Override 'makeEntity' to have IoC create entity instances.
	** Set 'strictMode' to 'true' to Err if the JSON contains unmapped data.
	static new make([Type:JsonConverter]? converters := null, [Str:Obj?]? options := null) {
		JsonConvertersImpl(converters ?: defConvs, options)
	}

	** Returns a new 'FomConverters' whose options are overridden with the given ones.
	abstract JsonConverters withOptions(Str:Obj? newOptions)
	
	** Returns the 'Converter' instance used to convert the given type. 
	@Operator
	abstract JsonConverter get(Type type)

	** The default set of JSON <-> Fantom converters.
	static Type:JsonConverter defConvs() {
		JsonConvertersImpl._defConvs
	}



	@NoDoc
	abstract Obj? toJsonCtx(Obj? fantomObj, JsonConverterCtx ctx)

	@NoDoc
	abstract Obj? fromJsonCtx(Obj? jsonVal, JsonConverterCtx ctx)
	
	

	** Converts the given Fantom object to its JSON representation.
	** 
	** 'fantomType' is required in case 'fantomObj' is null. 
	** 'fantomObj' is nullable so converters can create empty / default objects.
	abstract Obj? toJsonVal(Obj? fantomObj, Type fantomType)
	
	** Converts a JSON value to the given Fantom type.
	** 
	** 'jsonVal' is nullable so converters can choose whether or not to create empty lists and maps.
	abstract Obj? fromJsonVal(Obj? jsonVal, Type fantomType)

	
	** Converts the given Fantom object to its JSON representation.
	** 
	** 'fantomType' is required in case 'fantomObj' is null. 
	** 'fantomObj' is nullable so converters can create empty / default objects.
	abstract Str:Obj? toJsonObj(Obj? fantomObj, Type fantomType)
	
	** Converts a JSON object to the given Fantom type.
	** 
	** 'jsonObj' is nullable so converters can choose whether or not to create empty lists and maps.
	abstract Obj? fromJsonObj([Str:Obj?]? jsonObj, Type fantomType)
	
	

//	** Converts the given Fantom object to its JSON representation.
//	** 'null' values are converted to 'Remove.val'.
//	** 
//	** 'fantomType' is required in case 'fantomObj' is null. 
//	** 'fantomObj' is nullable so converters can create empty / default objects.
	abstract Str toJson(Obj? fantomObj, Type fantomType, Obj? options := null)
	
//	** Converts a JSON string to the given Fantom type.
//	** 
//	** 'json' is nullable so converters can choose whether or not to create empty lists and maps.
	abstract Obj? fromJson(Str json, Type fantomType)

}

@Js internal const class JsonConvertersImpl : JsonConverters {
	const CachingTypeLookup	typeLookup
	const JsonPropertyCache	propertyCache
	const Unsafe			optionsRef	// use Unsafe because JS can't handle immutable functions

	new make(|This| f) { f(this) }
	
	new makeArgs(Type:JsonConverter converters, [Str:Obj?]? options) {
		this.typeLookup = CachingTypeLookup(converters)
		this.optionsRef	= Unsafe(Str:Obj?[
			"afJson.makeEntity"		: |Type t, Field:Obj? vals->Obj?| { t.make([Field.makeSetFunc(vals)]) },
			"afJson.makeJsonObj"	: |-> Str:Obj?| { Str:Obj?[:] { ordered = true } },
			"afJson.makeMap"		: |Type t->Map| { Map((t.isGeneric ? Obj:Obj?# : t).toNonNullable) { it.ordered = true } },
			"afJson.strictMode"		: false,
			"afJson.propertyCache"	: JsonPropertyCache(),
		])
		
		if (options != null)
			this.optionsRef = Unsafe(this.options.rw.setAll(options))

		if (Env.cur.runtime != "js")
			// JS can't handle immutable functions, but I'd still like them to be thread safe in Java
			optionsRef = Unsafe(optionsRef.val.toImmutable)
		
		this.propertyCache	= this.options["afJson.propertyCache"]
	}

	Str:Obj? options() { optionsRef.val }
	
	override JsonConverters withOptions(Str:Obj? newOptions) {
		JsonConvertersImpl {
			it.optionsRef		= Unsafe(this.options.rw.setAll(newOptions))
			it.propertyCache	= it.options["afJson.propertyCache"] ?: this.propertyCache
			it.typeLookup		= this.typeLookup
		}
	}
	
	override Obj? toJsonCtx(Obj? fantomObj, JsonConverterCtx ctx) {
		get(ctx.type).toJsonVal(fantomObj, ctx)		
	}

	override Obj? fromJsonCtx(Obj? jsonVal, JsonConverterCtx ctx) {
		get(ctx.type).fromJsonVal(jsonVal, ctx)		
	}

	override Obj? toJsonVal(Obj? fantomObj, Type fantomType) {
		ctx := JsonConverterCtx.makeTop(this, fantomType, fantomObj, options)
		return toJsonCtx(fantomObj, ctx)
	}

	override Obj? fromJsonVal(Obj? jsonVal, Type fantomType) {
		ctx := JsonConverterCtx.makeTop(this, fantomType, jsonVal, options)
		return fromJsonCtx(jsonVal, ctx)
	}
	
	override Str:Obj? toJsonObj(Obj? fantomObj, Type fantomType) {
		toJsonVal(fantomObj, fantomType)
	}

	override Obj? fromJsonObj([Str:Obj?]? jsonObj, Type fantomType) {
		fromJsonVal(jsonObj, fantomType)
	}
	
	override Str toJson(Obj? fantomObj, Type fantomType, Obj? options := null) {
		throw UnsupportedErr()		
	}
	
	override Obj? fromJson(Str json, Type fantomType) {
		throw UnsupportedErr()
	}

	override JsonConverter get(Type type) {
		// if a specific converter can't be found then embed a record
		typeLookup.findParent(type)
	}
	
	static Type:JsonConverter _defConvs() {
		config				:= Type:JsonConverter[:]
		jsonLiteral			:= JsonLiteralConverter()

		// JSON Literals - https://json.org/
		config[Bool#]		= jsonLiteral
		config[Float#]		= jsonLiteral
		config[Decimal#]	= jsonLiteral
		config[Int#]		= jsonLiteral
		config[Num#]		= jsonLiteral
		config[Str#]		= jsonLiteral
		
		// Containers
		config[Obj#]		= JsonObjConverter()
//		config[Map#]		= FomMapConverter()
//		config[List#]		= FomListConverter()

		// Fantom Literals
		config[Date#]		= JsonSimpleConverter(Date#)
		config[DateTime#]	= JsonSimpleConverter(DateTime#)
		config[Depend#]		= JsonSimpleConverter(Depend#)
		config[Duration#]	= JsonSimpleConverter(Duration#)
		config[Enum#]		= JsonEnumConverter()
		config[Locale#]		= JsonSimpleConverter(Locale#)
		config[MimeType#]	= JsonSimpleConverter(MimeType#)
		config[Range#]		= JsonSimpleConverter(Range#)
		config[Regex#]		= JsonSimpleConverter(Regex#)
		config[Slot#]		= JsonSlotConverter()
		config[Time#]		= JsonSimpleConverter(Time#)
		config[TimeZone#]	= JsonSimpleConverter(TimeZone#)
		config[Type#]		= JsonTypeConverter()
		config[Unit#]		= JsonSimpleConverter(Unit#)
		config[Uri#]		= JsonSimpleConverter(Uri#)
		config[Uuid#]		= JsonSimpleConverter(Uuid#)
		config[Version#]	= JsonSimpleConverter(Version#)
		
		return config
	}
}