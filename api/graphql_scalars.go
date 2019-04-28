package api

import (
	"time"

	"github.com/graphql-go/graphql"
	"github.com/graphql-go/graphql/language/ast"
)

func serializeDateTime(value interface{}) interface{} {
	switch value := value.(type) {
	case time.Time:
		buff, err := value.MarshalText()
		if err != nil {
			return nil
		}

		return string(buff)
	case *time.Time:
		return serializeDateTime(*value)
	default:
		return nil
	}
}

func unserializeDateTime(value interface{}) interface{} {
	switch value := value.(type) {
	case []byte:
		t := time.Time{}
		err := t.UnmarshalText(value)
		if err != nil {
			return nil
		}

		return t
	case string:
		return unserializeDateTime([]byte(value))
	case *string:
		return unserializeDateTime([]byte(*value))
	default:
		return nil
	}
}

var dateTime = graphql.NewScalar(graphql.ScalarConfig{
	Name: "DateTime",
	Description: "The `DateTime` scalar type represents a DateTime." +
		" The DateTime is serialized as an RFC 3339 quoted string",
	Serialize:  serializeDateTime,
	ParseValue: unserializeDateTime,
	ParseLiteral: func(valueAST ast.Value) interface{} {
		switch valueAST := valueAST.(type) {
		case *ast.StringValue:
			return valueAST.Value
		}
		return nil
	},
})
