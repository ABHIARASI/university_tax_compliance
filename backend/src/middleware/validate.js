// validate(schema, 'body' | 'query' | 'params')
// Checks one part of the request against a Zod schema BEFORE the route runs.
//   fails -> the Zod error goes to the error handler -> 400 with field messages
//   passes -> the cleaned, typed data is put in req.valid.body / .query / .params
export const validate = (schema, where = 'body') => (req, res, next) => {
  const result = schema.safeParse(req[where] ?? {});
  if (!result.success) return next(result.error);
  req.valid = { ...(req.valid ?? {}), [where]: result.data };
  next();
};
