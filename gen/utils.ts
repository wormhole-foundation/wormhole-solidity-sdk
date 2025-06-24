const LOWER_TO_UPPER = /([a-z])([A-Z])/g;

export function toCapsSnakeCase(identifier: string) {
  //insert underscore between lowercase and uppercase letters and then capitalize all
  return identifier.replace(LOWER_TO_UPPER, '$1_$2').toUpperCase();
}
