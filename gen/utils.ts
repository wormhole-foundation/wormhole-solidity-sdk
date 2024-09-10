export function toCapsSnakeCase(identifier: string) {
  return identifier.split('').map((char, index) =>
    (  char === char.toUpperCase() //insert underscore before uppercase letters
    && char !== char.toLowerCase() //don't insert underscore before numbers
    && index !== 0                 //don't insert underscore at the beginning
    ) ? '_' + char : char.toUpperCase()
  ).join('');
}
