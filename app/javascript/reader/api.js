function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

export async function request(method, url, body = null, { keepalive = false } = {}) {
  const response = await fetch(url, {
    method,
    credentials: "same-origin",
    keepalive,
    headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken() },
    body: body ? JSON.stringify(body) : null
  })
  if (!response.ok) throw new Error(`${method} ${url} → ${response.status}`)
  return response.status === 204 ? null : response.json()
}
