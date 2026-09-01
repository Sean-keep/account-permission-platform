<template>
  <div>
    <div class="page-header">
      <h2>审计日志</h2>
    </div>

    <el-card shadow="never" class="filter-bar">
      <el-form :inline="true" :model="filter" size="default">
        <el-form-item label="操作人">
          <el-input v-model="filter.operator" placeholder="操作人" clearable style="width: 120px" @change="loadData" />
        </el-form-item>
        <el-form-item label="操作类型">
          <el-select v-model="filter.action" placeholder="全部" clearable style="width: 120px" @change="loadData">
            <el-option label="新建" value="create" />
            <el-option label="更新" value="update" />
            <el-option label="删除" value="delete" />
            <el-option label="绑定" value="bind" />
            <el-option label="解绑" value="unbind" />
            <el-option label="授权" value="grant" />
            <el-option label="撤销" value="revoke" />
            <el-option label="离职处理" value="resign" />
            <el-option label="批量撤销" value="batch_revoke" />
          </el-select>
        </el-form-item>
        <el-form-item label="对象类型">
          <el-select v-model="filter.target_type" placeholder="全部" clearable style="width: 120px" @change="loadData">
            <el-option label="人员" value="personnel" />
            <el-option label="系统" value="system" />
            <el-option label="账号" value="account" />
            <el-option label="权限" value="permission" />
            <el-option label="绑定关系" value="personnel_account" />
            <el-option label="授权关系" value="account_permission" />
          </el-select>
        </el-form-item>
        <el-form-item>
          <el-button type="primary" @click="loadData">查询</el-button>
          <el-button @click="resetFilter">重置</el-button>
        </el-form-item>
      </el-form>
    </el-card>

    <el-card shadow="never">
      <el-table :data="tableData" stripe v-loading="loading">
        <el-table-column prop="created_at" label="时间" width="180" />
        <el-table-column prop="operator" label="操作人" width="100" />
        <el-table-column prop="action" label="操作" width="100">
          <template #default="{ row }">
            <el-tag size="small" :type="actionTagType(row.action)">{{ actionLabel(row.action) }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="target_type" label="对象类型" width="100">
          <template #default="{ row }">
            {{ targetTypeLabel(row.target_type) }}
          </template>
        </el-table-column>
        <el-table-column prop="target_name" label="对象" width="150" />
        <el-table-column prop="detail" label="详情" show-overflow-tooltip />
      </el-table>
      <div class="pagination-wrap">
        <el-pagination v-model:current-page="pagination.page" v-model:page-size="pagination.page_size" :total="total" :page-sizes="[10, 20, 50, 100]" layout="total, sizes, prev, pager, next" @size-change="loadData" @current-change="loadData" />
      </div>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { auditLogsApi } from '../../api'

const loading = ref(false)
const tableData = ref<any[]>([])
const total = ref(0)

const filter = reactive({ operator: '', action: '', target_type: '' })
const pagination = reactive({ page: 1, page_size: 20 })

const actionMap: Record<string, { label: string; type: string }> = {
  create: { label: '新建', type: 'success' },
  update: { label: '更新', type: 'warning' },
  delete: { label: '删除', type: 'danger' },
  bind: { label: '绑定', type: '' },
  unbind: { label: '解绑', type: 'info' },
  grant: { label: '授权', type: 'success' },
  revoke: { label: '撤销', type: 'danger' },
  resign: { label: '离职处理', type: 'danger' },
  batch_revoke: { label: '批量撤销', type: 'danger' },
}

const targetTypeMap: Record<string, string> = {
  personnel: '人员',
  system: '系统',
  account: '账号',
  permission: '权限',
  personnel_account: '绑定关系',
  account_permission: '授权关系',
}

const actionLabel = (action: string) => actionMap[action]?.label || action
const actionTagType = (action: string) => (actionMap[action]?.type || '') as any
const targetTypeLabel = (t: string) => targetTypeMap[t] || t

const loadData = async () => {
  loading.value = true
  try {
    const res: any = await auditLogsApi.list({ ...filter, ...pagination })
    tableData.value = res.data?.items || []
    total.value = res.data?.total || 0
  } catch (e) {} finally { loading.value = false }
}

const resetFilter = () => {
  filter.operator = ''
  filter.action = ''
  filter.target_type = ''
  pagination.page = 1
  loadData()
}

onMounted(loadData)
</script>
