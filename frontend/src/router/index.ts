import { createRouter, createWebHistory } from 'vue-router'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'Login',
      component: () => import('../views/Login/index.vue'),
    },
    {
      path: '/',
      component: () => import('../components/Layout/MainLayout.vue'),
      redirect: '/dashboard',
      children: [
        { path: 'dashboard', name: 'Dashboard', component: () => import('../views/Dashboard/index.vue'), meta: { title: '工作台' } },
        { path: 'personnel', name: 'Personnel', component: () => import('../views/Personnel/index.vue'), meta: { title: '人员管理' } },
        { path: 'systems', name: 'Systems', component: () => import('../views/Systems/index.vue'), meta: { title: '系统管理' } },
        { path: 'accounts', name: 'Accounts', component: () => import('../views/Accounts/index.vue'), meta: { title: '账号管理' } },
        { path: 'audit-logs', name: 'AuditLogs', component: () => import('../views/AuditLogs/index.vue'), meta: { title: '审计日志' } },
        { path: 'personnel-ledger', name: 'PersonnelLedger', component: () => import('../views/PersonnelAccounts/index.vue'), meta: { title: '人员台账' } },
        { path: 'system-ledger', name: 'SystemLedger', component: () => import('../views/SystemPersonnel/index.vue'), meta: { title: '系统台账' } },
      ],
    },
  ],
})

// Navigation guard
router.beforeEach((to, _from, next) => {
  const token = localStorage.getItem('token')
  if (to.path !== '/login' && !token) {
    next('/login')
  } else if (to.path === '/login' && token) {
    next('/dashboard')
  } else {
    next()
  }
})

export default router
