
internal class TestJsonPropertyName : Test {
	
	Void testFromJson() {
		jsonObj := [
			"judge"	: "dude"
		]
		
		entity := (T_Entity09) JsonConverters().fromJsonVal(jsonObj, T_Entity09#)
		
		verifyEq(entity.wotever, 	"dude")
	}
	
	Void testToJson() {
		entity := T_Entity09() {
			wotever		= "dude"
		}
		
		folioRec := JsonConverters().toJsonObj(entity)
		
		verifyEq(folioRec["judge"],		"dude")
	}
}

internal class T_Entity09 {
	@JsonProperty { name="judge" }
			Str			wotever

	new make(|This|in) { in(this) }
}