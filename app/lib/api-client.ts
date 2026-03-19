export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message)
    this.name = 'ApiError'
  }
}

class ApiClient {
  private baseUrl: string
  private headers: Record<string, string>

  constructor() {
    this.baseUrl = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001'
    const credentials = process.env.NEXT_PUBLIC_API_BASIC_AUTH || 'admin:admin'
    const basicAuth = typeof btoa === 'function' ? btoa(credentials) : Buffer.from(credentials).toString('base64')
    this.headers = {
      'Authorization': `Basic ${basicAuth}`,
      'X-API-Key': process.env.NEXT_PUBLIC_API_KEY || '',
      'Content-Type': 'application/json',
    }
  }

  /** GET request. Paths starting with / are absolute (no prefix). Others get /api/v1/ prefix. */
  async get<T>(path: string, params?: Record<string, string>): Promise<T> {
    const url = this.buildUrl(path, params)
    const res = await fetch(url, { headers: this.headers })
    return this.handleResponse<T>(res)
  }

  /** POST request. Same path rules as get(). */
  async post<T>(path: string, body: unknown, params?: Record<string, string>): Promise<T> {
    const url = this.buildUrl(path, params)
    const res = await fetch(url, {
      method: 'POST',
      headers: this.headers,
      body: JSON.stringify(body),
    })
    return this.handleResponse<T>(res)
  }

  private buildUrl(path: string, params?: Record<string, string>): string {
    // /health, /ready → absolute (no prefix)
    // chains, tokens, strategies → prepend /api/v1/
    const fullPath = path.startsWith('/') ? path : `/api/v1/${path}`
    const url = new URL(fullPath, this.baseUrl)
    if (params) {
      for (const [key, value] of Object.entries(params)) {
        if (value !== undefined && value !== '') {
          url.searchParams.set(key, value)
        }
      }
    }
    return url.toString()
  }

  private async handleResponse<T>(res: Response): Promise<T> {
    if (!res.ok) {
      let code = 'UNKNOWN_ERROR'
      let message = `Request failed with status ${res.status}`
      try {
        const body = await res.json()
        if (body.error) code = body.error
        if (body.message) message = body.message
      } catch {
        // response body not JSON, use defaults
      }
      throw new ApiError(res.status, code, message)
    }
    return res.json() as Promise<T>
  }
}

export const api = new ApiClient()
