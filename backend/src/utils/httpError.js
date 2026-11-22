// An error that already knows which HTTP status to send.
// throw new HttpError(404, 'Bill not found')  ->  404 { error: 'Bill not found' }
export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}
