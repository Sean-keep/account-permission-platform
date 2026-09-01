<template>
  <div>
    <div class="page-header">
      <h2>账号管理</h2>
      <div>
        <el-button type="success" @click="importDialogVisible = true">批量导入</el-button>
        <el-button type="primary" @click="openDialog()">新建账号</el-button>
      </div>
    </div>

    <el-card shadow="never" class="filter-bar">
      <el-form :inline="true" :model="filter" size="default">
        <el-form-item label="搜索">
          <el-input v-model="filter.keyword" placeholder="账号名" clearable style="width: 160px" @change="loadData" />
        </el-form-item>
        <el-form-item label="系统">
          <el-select v-model="filter.system_id" placeholder="全部" clearable style="width: 150px" @change="loadData">
            <el-option v-for="s in systemOptions" :key="s.id" :label="s.name" :value="s.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="状态">
          <el-select v-model="filter.status" placeholder="全部" clearable style="width: 120px" @change="loadData">
            <el-option label="正常" value="active" />
            <el-option label="禁用" value="disabled" />
            <el-option label="待处理" value="resigned_pending" />
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
        <el-table-column prop="username" label="账号" width="150" />
        <el-table-column prop="system_name" label="所属系统" width="120" />
        <el-table-column prop="account_type" label="类型" width="100">
          <template #default="{ row }">
            {{ typeLabel(row.account_type) }}
          </template>
        </el-table-column>
        <el-table-column prop="status" label="状态" width="100" align="center">
          <template #default="{ row }">
            <el-tag :type="statusType(row.status)" size="small">{{ statusLabel(row.status) }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="remark" label="备注" show-overflow-tooltip />
        <el-table-column label="操作" width="220" fixed="right">
          <template #default="{ row }">
            <el-button type="primary" link size="small" @click="openDialog(row)">编辑</el-button>
            <el-button type="success" link size="small" @click="openBindPersonnel(row)">绑定人员</el-button>
            <el-button type="info" link size="small" @click="viewPermissions(row)">权限</el-button>
            <el-button type="danger" link size="small" @click="handleDelete(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
      <div class="pagination-wrap">
        <el-pagination v-model:current-page="pagination.page" v-model:page-size="pagination.page_size" :total="total" :page-sizes="[10, 20, 50]" layout="total, sizes, prev, pager, next" @size-change="loadData" @current-change="loadData" />
      </div>
    </el-card>

    <!-- Create/Edit Dialog -->
    <el-dialog v-model="dialogVisible" :title="isEdit ? '编辑账号' : '新建账号'" width="500px" destroy-on-close>
      <el-form ref="formRef" :model="form" :rules="rules" label-width="80px">
        <el-form-item label="账号名" prop="username">
          <el-input v-model="form.username" />
        </el-form-item>
        <el-form-item label="所属系统" prop="system_id">
          <el-select v-model="form.system_id" placeholder="选择系统" style="width: 100%">
            <el-option v-for="s in systemOptions" :key="s.id" :label="s.name" :value="s.id" />
          </el-select>
        </el-form-item>
        <el-form-item v-if="!isEdit" label="绑定人员">
          <el-select v-model="form.personnel_id" filterable clearable placeholder="选择人员（可选）" style="width: 100%">
            <el-option
              v-for="p in personnelOptions"
              :key="p.id"
              :label="`${p.name} (${p.employee_id}) - ${p.department}`"
              :value="p.id"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="类型">
          <el-select v-model="form.account_type" style="width: 100%">
            <el-option label="普通账号" value="normal" />
            <el-option label="管理员" value="admin" />
            <el-option label="服务账号" value="service" />
            <el-option label="共享账号" value="shared" />
          </el-select>
        </el-form-item>
        <el-form-item label="状态">
          <el-select v-model="form.status" style="width: 100%">
            <el-option label="正常" value="active" />
            <el-option label="禁用" value="disabled" />
          </el-select>
        </el-form-item>
        <el-form-item label="备注">
          <el-input v-model="form.remark" type="textarea" :rows="2" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="submitting" @click="handleSubmit">确定</el-button>
      </template>
    </el-dialog>

    <!-- Permissions Dialog -->
    <el-dialog v-model="permVisible" :title="`账号权限 - ${currentAccount}`" width="800px" destroy-on-close>
      <div style="margin-bottom: 12px">
        <el-button type="primary" size="small" @click="openGrantPerm">授予权限</el-button>
      </div>
      <el-table :data="accountPerms" stripe size="small">
        <el-table-column prop="permission_name" label="权限名称" />
        <el-table-column prop="permission_code" label="权限编码" />
        <el-table-column prop="category" label="分类" width="100" />
        <el-table-column prop="granted_date" label="授权日期" width="110" />
        <el-table-column prop="status" label="状态" width="80">
          <template #default="{ row }">
            <el-tag :type="row.status === 'active' ? 'success' : 'info'" size="small">
              {{ row.status === 'active' ? '有效' : '已撤销' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="100">
          <template #default="{ row }">
            <el-button v-if="row.status === 'active'" type="danger" link size="small" @click="revokePerm(row)">撤销</el-button>
          </template>
        </el-table-column>
      </el-table>
      <el-empty v-if="!accountPerms.length" description="暂无权限" />
    </el-dialog>

    <!-- Grant Permission Dialog -->
    <el-dialog v-model="grantPermVisible" title="授予权限" width="450px" destroy-on-close>
      <el-form :model="grantForm" label-width="80px">
        <el-form-item label="选择权限">
          <el-select v-model="grantForm.permission_id" filterable placeholder="搜索权限" style="width: 100%">
            <el-option v-for="p in permOptions" :key="p.id" :label="`${p.name} (${p.code})`" :value="p.id" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="grantPermVisible = false">取消</el-button>
        <el-button type="primary" :loading="submitting" @click="handleGrantPerm">授予</el-button>
      </template>
    </el-dialog>

    <!-- Bind Personnel Dialog -->
    <el-dialog v-model="bindPersonnelVisible" title="绑定人员" width="500px" destroy-on-close>
      <el-form :model="bindPersonnelForm" label-width="80px">
        <el-form-item label="选择人员">
          <el-select v-model="bindPersonnelForm.personnel_id" filterable placeholder="搜索人员" style="width: 100%">
            <el-option
              v-for="p in personnelOptions"
              :key="p.id"
              :label="`${p.name} (${p.employee_id}) - ${p.department}`"
              :value="p.id"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="绑定类型">
          <el-select v-model="bindPersonnelForm.bind_type" style="width: 100%">
            <el-option label="主要" value="primary" />
            <el-option label="次要" value="secondary" />
            <el-option label="临时" value="temporary" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="bindPersonnelVisible = false">取消</el-button>
        <el-button type="primary" :loading="submitting" @click="handleBindPersonnel">绑定</el-button>
      </template>
    </el-dialog>

    <!-- Import Dialog -->
    <el-dialog v-model="importDialogVisible" title="批量导入账号" width="600px" destroy-on-close>
      <div style="margin-bottom: 16px">
        <el-alert type="info" :closable="false">
          <template #title>
            <div>CSV 文件格式要求：</div>
            <div style="margin-top: 8px; font-size: 13px">
              <div>• 第一行为表头，数据从第二行开始</div>
              <div>• 列顺序：账号名, 系统名称, 账号类型, 备注</div>
              <div>• 账号名和系统名称为必填项</div>
              <div>• 账号类型可选：normal/admin/service/shared，默认 normal</div>
              <div>• 系统名称必须是已存在的系统</div>
            </div>
          </template>
        </el-alert>
      </div>

      <div style="margin-bottom: 16px">
        <el-button type="primary" link @click="downloadTemplate">
          <el-icon><Download /></el-icon>
          下载导入模板
        </el-button>
      </div>

      <el-upload
        ref="uploadRef"
        :auto-upload="false"
        :limit="1"
        accept=".csv"
        :on-change="handleFileChange"
        :on-exceed="() => ElMessage.warning('只能上传一个文件')"
        drag
      >
        <el-icon size="40"><Upload /></el-icon>
        <div style="margin-top: 8px">将 CSV 文件拖到此处，或<em>点击上传</em></div>
      </el-upload>

      <div v-if="importResult" style="margin-top: 16px">
        <el-alert
          :type="importResult.fail > 0 ? 'warning' : 'success'"
          :closable="false"
        >
          <template #title>
            <div>导入完成：成功 {{ importResult.success }} 个，失败 {{ importResult.fail }} 个</div>
          </template>
        </el-alert>
        <div v-if="importResult.errors?.length" style="margin-top: 8px; max-height: 150px; overflow-y: auto">
          <div v-for="(err, idx) in importResult.errors" :key="idx" style="color: #f56c6c; font-size: 13px; margin-bottom: 4px">
            {{ err }}
          </div>
        </div>
      </div>

      <template #footer>
        <el-button @click="importDialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="importing" @click="handleImport">开始导入</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { Download, Upload } from '@element-plus/icons-vue'
import { accountsApi, systemsApi, permissionsApi, relationsApi, personnelApi } from '../../api'

const loading = ref(false)
const submitting = ref(false)
const tableData = ref<any[]>([])
const total = ref(0)
const dialogVisible = ref(false)
const permVisible = ref(false)
const grantPermVisible = ref(false)
const bindPersonnelVisible = ref(false)
const importDialogVisible = ref(false)
const importing = ref(false)
const isEdit = ref(false)
const editId = ref(0)
const currentAccountId = ref(0)
const currentAccount = ref('')
const accountPerms = ref<any[]>([])
const systemOptions = ref<any[]>([])
const permOptions = ref<any[]>([])
const personnelOptions = ref<any[]>([])
const importFile = ref<File | null>(null)
const importResult = ref<any>(null)

const filter = reactive({ keyword: '', system_id: 0, status: '' })
const pagination = reactive({ page: 1, page_size: 20 })
const form = reactive({ username: '', system_id: null as any, personnel_id: null as any, account_type: 'normal', status: 'active', remark: '' })
const grantForm = reactive({ permission_id: null as any })
const bindPersonnelForm = reactive({ personnel_id: null as any, bind_type: 'primary' })

const rules = {
  username: [{ required: true, message: '请输入账号名', trigger: 'blur' }],
  system_id: [{ required: true, message: '请选择所属系统', trigger: 'change' }],
}

const typeLabel = (t: string) => ({ normal: '普通', admin: '管理员', service: '服务账号', shared: '共享' }[t] || t)
const statusLabel = (s: string) => ({ active: '正常', disabled: '禁用', locked: '锁定', resigned_pending: '待处理' }[s] || s)
const statusType = (s: string) => ({ active: 'success', disabled: 'info', locked: 'warning', resigned_pending: 'danger' }[s] || '') as any

const loadSystems = async () => {
  try {
    const res: any = await systemsApi.allList()
    systemOptions.value = res.data || []
  } catch (e) {}
}

const loadData = async () => {
  loading.value = true
  try {
    const params: any = { ...filter, ...pagination }
    if (!params.system_id) delete params.system_id
    const res: any = await accountsApi.list(params)
    tableData.value = res.data?.items || []
    total.value = res.data?.total || 0
  } catch (e) {} finally { loading.value = false }
}

const resetFilter = () => {
  filter.keyword = ''
  filter.system_id = 0
  filter.status = ''
  pagination.page = 1
  loadData()
}

const openDialog = (row?: any) => {
  isEdit.value = !!row
  if (row) {
    editId.value = row.id
    Object.assign(form, row)
  } else {
    editId.value = 0
    Object.assign(form, { username: '', system_id: null, personnel_id: null, account_type: 'normal', status: 'active', remark: '' })
  }
  loadPersonnelOptions()
  dialogVisible.value = true
}

const handleSubmit = async () => {
  submitting.value = true
  try {
    if (isEdit.value) {
      await accountsApi.update(editId.value, form)
      ElMessage.success('更新成功')
    } else {
      const res: any = await accountsApi.create(form)
      const newAccountId = res.data?.id
      // 如果选择了人员，自动绑定
      if (form.personnel_id && newAccountId) {
        await relationsApi.bindAccount({
          account_id: newAccountId,
          personnel_id: form.personnel_id,
          bind_type: 'primary'
        })
        ElMessage.success('创建成功，已自动绑定人员')
      } else {
        ElMessage.success('创建成功')
      }
    }
    dialogVisible.value = false
    loadData()
  } catch (e) {} finally { submitting.value = false }
}

const handleDelete = async (row: any) => {
  await ElMessageBox.confirm(`确定删除账号「${row.username}」?`, '确认')
  await accountsApi.delete(row.id)
  ElMessage.success('删除成功')
  loadData()
}

const viewPermissions = async (row: any) => {
  currentAccountId.value = row.id
  currentAccount.value = row.username
  try {
    const res: any = await accountsApi.getPermissions(row.id)
    accountPerms.value = res.data || []
    permVisible.value = true
  } catch (e) {}
}

const openGrantPerm = async () => {
  grantForm.permission_id = null
  try {
    const res: any = await permissionsApi.allList()
    permOptions.value = res.data || []
  } catch (e) {}
  grantPermVisible.value = true
}

const handleGrantPerm = async () => {
  if (!grantForm.permission_id) {
    ElMessage.warning('请选择权限')
    return
  }
  submitting.value = true
  try {
    await relationsApi.grantPermission({
      account_id: currentAccountId.value,
      permission_id: grantForm.permission_id,
    })
    ElMessage.success('授权成功')
    grantPermVisible.value = false
    // Reload permissions
    const res: any = await accountsApi.getPermissions(currentAccountId.value)
    accountPerms.value = res.data || []
  } catch (e) {} finally { submitting.value = false }
}

const revokePerm = async (row: any) => {
  await ElMessageBox.confirm(`确定撤销权限「${row.permission_name}」?`, '确认')
  await relationsApi.revokePermission(row.link_id, '手动撤销')
  ElMessage.success('撤销成功')
  const res: any = await accountsApi.getPermissions(currentAccountId.value)
  accountPerms.value = res.data || []
}

const loadPersonnelOptions = async () => {
  try {
    const res: any = await personnelApi.list({ page: 1, page_size: 200 })
    personnelOptions.value = res.data?.items || []
  } catch (e) {}
}

const openBindPersonnel = async (row: any) => {
  currentAccountId.value = row.id
  currentAccount.value = row.username
  bindPersonnelForm.personnel_id = null
  bindPersonnelForm.bind_type = 'primary'
  await loadPersonnelOptions()
  bindPersonnelVisible.value = true
}

const handleBindPersonnel = async () => {
  if (!bindPersonnelForm.personnel_id) {
    ElMessage.warning('请选择人员')
    return
  }
  submitting.value = true
  try {
    await relationsApi.bindAccount({
      personnel_id: bindPersonnelForm.personnel_id,
      account_id: currentAccountId.value,
      bind_type: bindPersonnelForm.bind_type,
    })
    ElMessage.success('绑定成功')
    bindPersonnelVisible.value = false
  } catch (e) {} finally { submitting.value = false }
}

const handleFileChange = (file: any) => {
  importFile.value = file.raw
  importResult.value = null
}

const downloadTemplate = () => {
  const csvContent = '账号名,系统名称,账号类型,备注\n示例用户,OA系统,normal,示例备注\n'
  const blob = new Blob(['﻿' + csvContent], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = '账号导入模板.csv'
  link.click()
  URL.revokeObjectURL(url)
}

const handleImport = async () => {
  if (!importFile.value) {
    ElMessage.warning('请选择要导入的文件')
    return
  }
  importing.value = true
  try {
    const formData = new FormData()
    formData.append('file', importFile.value)
    const res: any = await accountsApi.import(formData)
    importResult.value = res.data
    if (res.data?.success > 0) {
      loadData()
    }
  } catch (e) {} finally { importing.value = false }
}

onMounted(() => {
  loadSystems()
  loadData()
})
</script>
