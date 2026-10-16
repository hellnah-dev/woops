/// Government photo IDs accepted for the age check, by country (ISO 3166-1).
/// Every list also accepts a passport. Countries not listed get [_fallback].
const _byCountry = <String, List<String>>{
  'IN': ['Aadhaar card', 'PAN card', 'Driving licence', 'Voter ID (EPIC)'],
  'NP': ['Citizenship certificate', 'National ID (NID)', 'Driving licence'],
  'BD': ['National ID card', 'Driving licence'],
  'PK': ['CNIC', 'Driving licence'],
  'LK': ['National identity card', 'Driving licence'],
  'US': ['Driver’s license', 'State ID card', 'Passport card'],
  'CA': ['Driver’s licence', 'Provincial photo ID card'],
  'GB': ['Driving licence', 'Biometric residence permit', 'CitizenCard (PASS)'],
  'IE': ['Driving licence', 'Public Services Card'],
  'AU': ['Driver licence', 'Proof of age card'],
  'NZ': ['Driver licence', 'Kiwi Access card'],
  'DE': ['Personalausweis', 'Führerschein', 'Aufenthaltstitel'],
  'FR': ['Carte nationale d’identité', 'Permis de conduire', 'Titre de séjour'],
  'ES': ['DNI', 'NIE', 'Permiso de conducir'],
  'IT': ['Carta d’identità', 'Patente di guida'],
  'NL': ['Identiteitskaart', 'Rijbewijs'],
  'BR': ['RG', 'CNH (driver’s licence)'],
  'MX': ['INE voter card', 'Driver’s licence'],
  'JP': ['My Number card', 'Driver’s licence', 'Residence card'],
  'KR': ['Resident registration card', 'Driver’s licence'],
  'CN': ['Resident identity card'],
  'SG': ['NRIC', 'FIN card', 'Driving licence'],
  'MY': ['MyKad', 'Driving licence'],
  'PH': ['PhilSys national ID', 'Driver’s license', 'UMID'],
  'ID': ['KTP', 'SIM (driving licence)'],
  'TH': ['Thai national ID card', 'Driving licence'],
  'VN': ['Citizen identity card', 'Driving licence'],
  'AE': ['Emirates ID'],
  'SA': ['National ID', 'Iqama'],
  'EG': ['National ID card', 'Driving licence'],
  'NG': ['NIN slip / card', 'Driver’s licence', 'Voter’s card'],
  'KE': ['National ID card', 'Driving licence'],
  'ZA': ['Smart ID card', 'Green ID book', 'Driving licence'],
};

const _fallback = ['National ID card', 'Driving licence', 'Residence permit'];

/// Accepted documents for [countryCode], passport first.
List<String> idDocumentsFor(String? countryCode) => [
  'Passport',
  ...(_byCountry[countryCode?.toUpperCase()] ?? _fallback),
];
