<template>
  <div>
    <div class="page-header">
      <h2>人员台账</h2>
    </div>

    <!-- Personnel Selector -->
    <el-card shadow="never" style="margin-bottom: 16px">
      <el-form :inline="true" size="default">
        <el-form-item label="选择人员">
          <el-select
            v-model="selectedPersonnelId"
            filterable
            remote
            :remote-method="searchPersonnel"
            placeholder="搜索姓名或工号"
            style="width: 300px"
            @change="loadPersonnelAccounts"
            :loading="searching"
          >
            <el-option
              v-for="p in personnelOptions"
              :key="p.id"
              :label="`${p.name} (${p.employee_id}) - ${p.department}`"
              :value="p.id"
            />
          </el-select>
        </el-form-item>
      </el-form>
    </el-card>

    <!-- Personnel Info -->
    <el-row :gutter="16" v-if="personnelInfo" style="margin-bottom: 16px; display: flex; align-items: stretch">
      <el-col :span="6">
        <el-card shadow="hover">
          <div class="info-item"><span class="label">姓名：</span>{{ personnelInfo.name }}</div>
          <div class="info-item"><span class="label">工号：</span>{{ personnelInfo.employee_id }}</div>
          <div class="info-item"><span class="label">部门：</span>{{ personnelInfo.department }}</div>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="hover">
          <div class="info-item"><span class="label">职位：</span>{{ personnelInfo.position || '-' }}</div>
          <div class="info-item"><span class="label">邮箱：</span>{{ personnelInfo.email || '-' }}</div>
          <div class="info-item"><span class="label">手机：</span>{{ personnelInfo.phone || '-' }}</div>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="hover">
          <div class="info-item">
            <span class="label">状态：</span>
            <span :style="{ color: personnelInfo.status === 'active' ? '#67c23a' : '#f56c6c' }">
              {{ personnelInfo.status === 'active' ? '● 在职' : '○ 离职' }}
            </span>
          </div>
          <div class="info-item"><span class="label">入职日期：</span>{{ personnelInfo.entry_date || '-' }}</div>
          <div class="info-item"><span class="label">离职日期：</span>{{ personnelInfo.resign_date || '-' }}</div>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="hover" class="stat-card-compact">
          <div class="stat-number-compact">{{ accounts.length }}</div>
          <div class="stat-label-compact">关联账号数</div>
        </el-card>
      </el-col>
    </el-row>

    <!-- Accounts Table -->
    <el-card shadow="never">
      <template #header>
        <span>关联账号列表</span>
      </template>
      <el-table :data="accounts" stripe v-loading="loading" style="width: 100%">
        <el-table-column prop="username" label="账号" />
        <el-table-column prop="system_name" label="所属系统" />
        <el-table-column prop="bind_type" label="绑定类型">
          <template #default="{ row }">
            <el-tag size="small" :type="bindTypeTag(row.bind_type)">{{ bindTypeLabel(row.bind_type) }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="bind_status" label="绑定状态">
          <template #default="{ row }">
            <el-tag :type="row.bind_status === 'active' ? 'success' : 'info'" size="small">
              {{ row.bind_status === 'active' ? '有效' : '已解绑' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="account_status" label="账号状态">
          <template #default="{ row }">
            <el-tag :type="accountStatusType(row.account_status)" size="small">
              {{ accountStatusLabel(row.account_status) }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="bind_date" label="绑定日期" />
        <el-table-column prop="unbind_date" label="解绑日期" />
        <el-table-column label="操作" width="100">
          <template #default="{ row }">
            <el-button type="primary" link size="small" @click="viewAccountPermissions(row)">查看权限</el-button>
          </template>
        </el-table-column>
      </el-table>
      <el-empty v-if="!accounts.length && personnelInfo" description="该人员暂无关联账号" />
      <el-empty v-if="!personnelInfo" description="请先选择人员" />
    </el-card>

    <!-- Account Permissions Dialog -->
    <el-dialog v-model="permVisible" :title="`账号权限 - ${currentAccount}`" width="700px" destroy-on-close>
      <el-table :data="accountPerms" stripe size="small">
        <el-table-column prop="permission_name" label="权限名称" width="150" />
        <el-table-column prop="permission_code" label="权限编码" width="150" />
        <el-table-column prop="category" label="分类" width="100" />
        <el-table-column prop="granted_date" label="授权日期" width="110" />
        <el-table-column prop="status" label="状态" width="80">
          <template #default="{ row }">
            <el-tag :type="row.status === 'active' ? 'success' : 'info'" size="small">
              {{ row.status === 'active' ? '有效' : '已撤销' }}
            </el-tag>
          </template>
        </el-table-column>
      </el-table>
      <el-empty v-if="!accountPerms.length" description="该账号暂无权限" />
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { personnelApi, accountsApi } from '../../api'

const loading = ref(false)
const searching = ref(false)
const selectedPersonnelId = ref<number | null>(null)
const personnelOptions = ref<any[]>([])
const personnelInfo = ref<any>(null)
const accounts = ref<any[]>([])
const permVisible = ref(false)
const accountPerms = ref<any[]>([])
const currentAccount = ref('')

const bindTypeLabel = (t: string) => ({ primary: '主要', secondary: '次要', temporary: '临时' }[t] || t)
const bindTypeTag = (t: string) => ({ primary: '', secondary: 'warning', temporary: 'info' }[t] || '') as any
const accountStatusLabel = (s: string) => ({ active: '正常', disabled: '禁用', locked: '锁定', resigned_pending: '待处理' }[s] || s)
const accountStatusType = (s: string) => ({ active: 'success', disabled: 'info', locked: 'warning', resigned_pending: 'danger' }[s] || '') as any

const searchPersonnel = async (query: string) => {
  if (!query) return
  searching.value = true
  try {
    const res: any = await personnelApi.list({ keyword: query, page: 1, page_size: 50 })
    personnelOptions.value = res.data?.items || []
  } catch (e) {} finally { searching.value = false }
}

const loadPersonnelAccounts = async () => {
  if (!selectedPersonnelId.value) return
  loading.value = true
  try {
    // Get personnel info
    const pRes: any = await personnelApi.get(selectedPersonnelId.value)
    personnelInfo.value = pRes.data

    // Get accounts
    const aRes: any = await personnelApi.getAccounts(selectedPersonnelId.value)
    accounts.value = aRes.data || []
  } catch (e) {} finally { loading.value = false }
}

const viewAccountPermissions = async (row: any) => {
  currentAccount.value = row.username
  try {
    const res: any = await accountsApi.getPermissions(row.account_id)
    accountPerms.value = res.data || []
    permVisible.value = true
  } catch (e) {}
}

onMounted(() => {
  // Load all personnel for initial options
  personnelApi.list({ page: 1, page_size: 100 }).then((res: any) => {
    personnelOptions.value = res.data?.items || []
  })
})
</script>

<style scoped>
.info-item {
  margin-bottom: 8px;
  font-size: 14px;
}
.info-item .label {
  color: #909399;
  margin-right: 8px;
}
.stat-card-compact {
  text-align: center;
  padding: 12px 20px;
}
.stat-number-compact {
  font-size: 24px;
  font-weight: 700;
  color: #409eff;
}
.stat-label-compact {
  font-size: 13px;
  color: #909399;
  margin-top: 4px;
}
</style>
