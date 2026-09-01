import axios from 'axios'
import { ElMessage } from 'element-plus'
import router from '../router'

const request = axios.create({
  baseURL: '/api',
  timeout: 30000,
})

// Request interceptor - add token
request.interceptors.request.use((config) => {
  const token = localStorage.getItem('token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

// Response interceptor
request.interceptors.response.use(
  (response) => {
    const data = response.data
    if (data.code && data.code !== 200) {
      if (data.code === 401) {
        localStorage.removeItem('token')
        localStorage.removeItem('user')
        router.push('/login')
      }
      ElMessage.error(data.msg || '请求失败')
      return Promise.reject(new Error(data.msg))
    }
    return data
  },
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('token')
      localStorage.removeItem('user')
      router.push('/login')
    }
    ElMessage.error(error.response?.data?.detail || error.message || '网络错误')
    return Promise.reject(error)
  }
)

// ==================== Auth ====================
export const authApi = {
  login: (data: { username: string; password: string }) => request.post('/auth/login', data),
  me: () => request.get('/auth/me'),
  changePassword: (data: { old_password: string; new_password: string }) => request.post('/auth/change-password', data),
}

// ==================== Personnel ====================
export const personnelApi = {
  list: (params: any) => request.get('/personnel', { params }),
  get: (id: number) => request.get(`/personnel/${id}`),
  create: (data: any) => request.post('/personnel', data),
  update: (id: number, data: any) => request.put(`/personnel/${id}`, data),
  delete: (id: number) => request.delete(`/personnel/${id}`),
  resign: (id: number, data: any) => request.post(`/personnel/${id}/resign`, data),
  getAccounts: (id: number) => request.get(`/personnel/${id}/accounts`),
}

// ==================== Systems ====================
export const systemsApi = {
  list: (params: any) => request.get('/systems', { params }),
  get: (id: number) => request.get(`/systems/${id}`),
  create: (data: any) => request.post('/systems', data),
  update: (id: number, data: any) => request.put(`/systems/${id}`, data),
  delete: (id: number) => request.delete(`/systems/${id}`),
  allList: () => request.get('/systems/all/list'),
  getPersonnel: (id: number) => request.get(`/systems/${id}/personnel`),
}

// ==================== Accounts ====================
export const accountsApi = {
  list: (params: any) => request.get('/accounts', { params }),
  get: (id: number) => request.get(`/accounts/${id}`),
  create: (data: any) => request.post('/accounts', data),
  update: (id: number, data: any) => request.put(`/accounts/${id}`, data),
  delete: (id: number) => request.delete(`/accounts/${id}`),
  getPermissions: (id: number) => request.get(`/accounts/${id}/permissions`),
}

// ==================== Permissions ====================
export const permissionsApi = {
  list: (params: any) => request.get('/permissions', { params }),
  create: (data: any) => request.post('/permissions', data),
  update: (id: number, data: any) => request.put(`/permissions/${id}`, data),
  delete: (id: number) => request.delete(`/permissions/${id}`),
  allList: (systemId?: number) => request.get('/permissions/all/list', { params: { system_id: systemId } }),
}

// ==================== Relations ====================
export const relationsApi = {
  bindAccount: (data: any) => request.post('/relations/bind-account', data),
  unbindAccount: (bindId: number) => request.post(`/relations/unbind-account?bind_id=${bindId}`),
  grantPermission: (data: any) => request.post('/relations/grant-permission', data),
  revokePermission: (linkId: number, reason?: string) => request.post(`/relations/revoke-permission?link_id=${linkId}&reason=${reason || ''}`),
  batchRevoke: (data: any) => request.post('/relations/batch-revoke', data),
}

// ==================== Audit Logs ====================
export const auditLogsApi = {
  list: (params: any) => request.get('/audit-logs', { params }),
}

// ==================== Dashboard ====================
export const dashboardApi = {
  stats: () => request.get('/dashboard/stats'),
  departments: () => request.get('/dashboard/departments'),
}
