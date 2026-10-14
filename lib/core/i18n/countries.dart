import 'dart:ui' show PlatformDispatcher;

/// A country (ISO 3166-1 alpha-2).
class Country {
  const Country(this.code, this.name);

  final String code;
  final String name;

  /// Flag emoji built from the two regional-indicator letters.
  String get flag => String.fromCharCodes(code.codeUnits.map((c) => 0x1F1E6 + c - 0x41));

  @override
  bool operator ==(Object other) => other is Country && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

const _data = '''
AF|Afghanistan
AX|Åland Islands
AL|Albania
DZ|Algeria
AS|American Samoa
AD|Andorra
AO|Angola
AI|Anguilla
AG|Antigua and Barbuda
AR|Argentina
AM|Armenia
AW|Aruba
AU|Australia
AT|Austria
AZ|Azerbaijan
BS|Bahamas
BH|Bahrain
BD|Bangladesh
BB|Barbados
BY|Belarus
BE|Belgium
BZ|Belize
BJ|Benin
BM|Bermuda
BT|Bhutan
BO|Bolivia
BQ|Caribbean Netherlands
BA|Bosnia and Herzegovina
BW|Botswana
BR|Brazil
IO|British Indian Ocean Territory
VG|British Virgin Islands
BN|Brunei
BG|Bulgaria
BF|Burkina Faso
BI|Burundi
CV|Cape Verde
KH|Cambodia
CM|Cameroon
CA|Canada
KY|Cayman Islands
CF|Central African Republic
TD|Chad
CL|Chile
CN|China
CX|Christmas Island
CC|Cocos (Keeling) Islands
CO|Colombia
KM|Comoros
CG|Congo - Brazzaville
CD|Congo - Kinshasa
CK|Cook Islands
CR|Costa Rica
CI|Côte d’Ivoire
HR|Croatia
CU|Cuba
CW|Curaçao
CY|Cyprus
CZ|Czechia
DK|Denmark
DJ|Djibouti
DM|Dominica
DO|Dominican Republic
EC|Ecuador
EG|Egypt
SV|El Salvador
GQ|Equatorial Guinea
ER|Eritrea
EE|Estonia
SZ|Eswatini
ET|Ethiopia
FK|Falkland Islands
FO|Faroe Islands
FJ|Fiji
FI|Finland
FR|France
GF|French Guiana
PF|French Polynesia
GA|Gabon
GM|Gambia
GE|Georgia
DE|Germany
GH|Ghana
GI|Gibraltar
GR|Greece
GL|Greenland
GD|Grenada
GP|Guadeloupe
GU|Guam
GT|Guatemala
GG|Guernsey
GN|Guinea
GW|Guinea-Bissau
GY|Guyana
HT|Haiti
HN|Honduras
HK|Hong Kong
HU|Hungary
IS|Iceland
IN|India
ID|Indonesia
IR|Iran
IQ|Iraq
IE|Ireland
IM|Isle of Man
IL|Israel
IT|Italy
JM|Jamaica
JP|Japan
JE|Jersey
JO|Jordan
KZ|Kazakhstan
KE|Kenya
KI|Kiribati
XK|Kosovo
KW|Kuwait
KG|Kyrgyzstan
LA|Laos
LV|Latvia
LB|Lebanon
LS|Lesotho
LR|Liberia
LY|Libya
LI|Liechtenstein
LT|Lithuania
LU|Luxembourg
MO|Macao
MG|Madagascar
MW|Malawi
MY|Malaysia
MV|Maldives
ML|Mali
MT|Malta
MH|Marshall Islands
MQ|Martinique
MR|Mauritania
MU|Mauritius
YT|Mayotte
MX|Mexico
FM|Micronesia
MD|Moldova
MC|Monaco
MN|Mongolia
ME|Montenegro
MS|Montserrat
MA|Morocco
MZ|Mozambique
MM|Myanmar
NA|Namibia
NR|Nauru
NP|Nepal
NL|Netherlands
NC|New Caledonia
NZ|New Zealand
NI|Nicaragua
NE|Niger
NG|Nigeria
NU|Niue
NF|Norfolk Island
KP|North Korea
MK|North Macedonia
MP|Northern Mariana Islands
NO|Norway
OM|Oman
PK|Pakistan
PW|Palau
PS|Palestine
PA|Panama
PG|Papua New Guinea
PY|Paraguay
PE|Peru
PH|Philippines
PN|Pitcairn Islands
PL|Poland
PT|Portugal
PR|Puerto Rico
QA|Qatar
RE|Réunion
RO|Romania
RU|Russia
RW|Rwanda
WS|Samoa
SM|San Marino
ST|São Tomé and Príncipe
SA|Saudi Arabia
SN|Senegal
RS|Serbia
SC|Seychelles
SL|Sierra Leone
SG|Singapore
SX|Sint Maarten
SK|Slovakia
SI|Slovenia
SB|Solomon Islands
SO|Somalia
ZA|South Africa
KR|South Korea
SS|South Sudan
ES|Spain
LK|Sri Lanka
BL|St. Barthélemy
SH|St. Helena
KN|St. Kitts and Nevis
LC|St. Lucia
MF|St. Martin
PM|St. Pierre and Miquelon
VC|St. Vincent and the Grenadines
SD|Sudan
SR|Suriname
SJ|Svalbard and Jan Mayen
SE|Sweden
CH|Switzerland
SY|Syria
TW|Taiwan
TJ|Tajikistan
TZ|Tanzania
TH|Thailand
TL|Timor-Leste
TG|Togo
TK|Tokelau
TO|Tonga
TT|Trinidad and Tobago
TN|Tunisia
TR|Türkiye
TM|Turkmenistan
TC|Turks and Caicos Islands
TV|Tuvalu
UG|Uganda
UA|Ukraine
AE|United Arab Emirates
GB|United Kingdom
US|United States
VI|U.S. Virgin Islands
UY|Uruguay
UZ|Uzbekistan
VU|Vanuatu
VA|Vatican City
VE|Venezuela
VN|Vietnam
WF|Wallis and Futuna
EH|Western Sahara
YE|Yemen
ZM|Zambia
ZW|Zimbabwe
''';

/// All countries, sorted by name.
final List<Country> allCountries = (() {
  final list = _data
      .trim()
      .split('\n')
      .map((line) => line.split('|'))
      .map((p) => Country(p[0], p[1]))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return List<Country>.unmodifiable(list);
})();

final Map<String, Country> _byCode = {for (final c in allCountries) c.code: c};

Country? countryByCode(String? code) => code == null ? null : _byCode[code.toUpperCase()];

/// The device's region (e.g. "NP" from ne-NP / en-NP), if known.
String? deviceCountryCode() {
  final code = PlatformDispatcher.instance.locale.countryCode;
  return code != null && _byCode.containsKey(code.toUpperCase()) ? code.toUpperCase() : null;
}
