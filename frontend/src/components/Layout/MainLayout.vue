<template>
  <el-container style="height: 100vh">
    <!-- Sidebar -->
    <el-aside :width="isCollapse ? '64px' : '220px'" style="transition: width 0.3s; background: #001529">
      <div class="logo" :class="{ collapsed: isCollapse }">
        <el-icon size="24" color="#409eff"><Key /></el-icon>
        <span v-if="!isCollapse" class="logo-text">权限台账</span>
      </div>
      <el-menu
        :default-active="currentRoute"
        :collapse="isCollapse"
        background-color="#001529"
        text-color="#ffffffa6"
        active-text-color="#fff"
        router
        :collapse-transition="false"
      >
        <el-menu-item index="/dashboard">
          <el-icon><DataBoard /></el-icon>
          <template #title>工作台</template>
        </el-menu-item>
        <el-menu-item index="/personnel-ledger">
          <el-icon><UserFilled /></el-icon>
          <template #title>人员台账</template>
        </el-menu-item>
        <el-menu-item index="/system-ledger">
          <el-icon><OfficeBuilding /></el-icon>
          <template #title>系统台账</template>
        </el-menu-item>
        <el-menu-item index="/personnel">
          <el-icon><User /></el-icon>
          <template #title>人员管理</template>
        </el-menu-item>
        <el-menu-item index="/systems">
          <el-icon><Monitor /></el-icon>
          <template #title>系统管理</template>
        </el-menu-item>
        <el-menu-item index="/accounts">
          <el-icon><Avatar /></el-icon>
          <template #title>账号管理</template>
        </el-menu-item>
        <el-menu-item index="/audit-logs">
          <el-icon><Document /></el-icon>
          <template #title>审计日志</template>
        </el-menu-item>
      </el-menu>
    </el-aside>

    <!-- Main Content -->
    <el-container>
      <el-header style="display: flex; align-items: center; justify-content: space-between; background: #fff; border-bottom: 1px solid #e8e8e8; padding: 0 20px">
        <div style="display: flex; align-items: center">
          <el-icon
            size="20"
            style="cursor: pointer; margin-right: 16px"
            @click="isCollapse = !isCollapse"
          >
            <Fold v-if="!isCollapse" />
            <Expand v-else />
          </el-icon>
          <span style="font-size: 16px; font-weight: 500">{{ currentTitle }}</span>
        </div>
        <div style="display: flex; align-items: center">
          <span style="margin-right: 16px; color: #666">{{ currentUser?.nickname || currentUser?.username }}</span>
          <el-button type="primary" link @click="pwdDialogVisible = true" style="margin-right: 16px">
            <el-icon><Lock /></el-icon>
            修改密码
          </el-button>
          <el-button type="danger" link @click="handleLogout">
            <el-icon><SwitchButton /></el-icon>
            退出
          </el-button>
        </div>
      </el-header>

    <!-- 修改密码弹窗 -->
    <el-dialog v-model="pwdDialogVisible" title="修改密码" width="400px" destroy-on-close>
      <el-form ref="pwdFormRef" :model="pwdForm" :rules="pwdRules" label-width="80px">
        <el-form-item label="原密码" prop="old_password">
          <el-input v-model="pwdForm.old_password" type="password" show-password />
        </el-form-item>
        <el-form-item label="新密码" prop="new_password">
          <el-input v-model="pwdForm.new_password" type="password" show-password />
        </el-form-item>
        <el-form-item label="确认密码" prop="confirm_password">
          <el-input v-model="pwdForm.confirm_password" type="password" show-password />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="pwdDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="pwdLoading" @click="handleChangePassword">确定</el-button>
      </template>
    </el-dialog>
      <el-main style="background: #f5f7fa; padding: 20px">
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<script setup lang="ts">
import { computed, ref, reactive } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { authApi } from '../../api'

const route = useRoute()
const router = useRouter()
const isCollapse = ref(false)

const currentRoute = computed(() => route.path)
const currentTitle = computed(() => (route.meta?.title as string) || '工作台')

const currentUser = computed(() => {
  try {
    return JSON.parse(localStorage.getItem('user') || '{}')
  } catch {
    return {}
  }
})

const handleLogout = () => {
  localStorage.removeItem('token')
  localStorage.removeItem('user')
  router.push('/login')
}

// 修改密码
const pwdDialogVisible = ref(false)
const pwdLoading = ref(false)
const pwdFormRef = ref()
const pwdForm = reactive({
  old_password: '',
  new_password: '',
  confirm_password: ''
})

const pwdRules = {
  old_password: [{ required: true, message: '请输入原密码', trigger: 'blur' }],
  new_password: [
    { required: true, message: '请输入新密码', trigger: 'blur' },
    { min: 6, message: '密码长度不能少于6位', trigger: 'blur' }
  ],
  confirm_password: [
    { required: true, message: '请确认新密码', trigger: 'blur' },
    {
      validator: (_rule: any, value: string, callback: Function) => {
        if (value !== pwdForm.new_password) {
          callback(new Error('两次输入的密码不一致'))
        } else {
          callback()
        }
      },
      trigger: 'blur'
    }
  ]
}

const handleChangePassword = async () => {
  await pwdFormRef.value?.validate()
  pwdLoading.value = true
  try {
    await authApi.changePassword({
      old_password: pwdForm.old_password,
      new_password: pwdForm.new_password
    })
    ElMessage.success('密码修改成功，请重新登录')
    pwdDialogVisible.value = false
    // 清空表单
    pwdForm.old_password = ''
    pwdForm.new_password = ''
    pwdForm.confirm_password = ''
    // 退出登录
    localStorage.removeItem('token')
    localStorage.removeItem('user')
    router.push('/login')
  } catch (e) {} finally { pwdLoading.value = false }
}
</script>

<style scoped>
.logo {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 56px;
  padding: 0 16px;
  gap: 10px;
  border-bottom: 1px solid #ffffff1a;
}

.logo.collapsed {
  padding: 0;
}

.logo-text {
  color: #fff;
  font-size: 16px;
  font-weight: 600;
  white-space: nowrap;
}

:deep(.el-menu) {
  border-right: none;
}

:deep(.el-menu-item.is-active) {
  background-color: #1890ff !important;
}
</style>
