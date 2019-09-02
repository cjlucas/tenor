module TimeFormatter exposing
    ( Builder(..)
    , Internal
    , format
    , withFormat
    , withLocale
    , withZone
    )

import Time
import Time.Format
import Time.Format.Config exposing (Config)
import Time.Format.Config.Config_en_us as Config_en_us


type Builder
    = Builder Internal


type Locale
    = EN_US


type alias Internal =
    { format : String
    , locale : Locale
    , zone : Time.Zone
    }


withFormat : String -> Builder
withFormat formatStr =
    Builder
        { format = formatStr
        , locale = EN_US
        , zone = Time.utc
        }


withZone : Builder -> Time.Zone -> Builder
withZone (Builder internal) zone =
    Builder { internal | zone = zone }


withLocale : Builder -> Locale -> Builder
withLocale (Builder internal) locale =
    Builder { internal | locale = locale }


format : Builder -> Time.Posix -> String
format (Builder internal) =
    Time.Format.format
        (localeConfig internal.locale)
        internal.format
        internal.zone


localeConfig locale =
    case locale of
        EN_US ->
            Config_en_us.config
