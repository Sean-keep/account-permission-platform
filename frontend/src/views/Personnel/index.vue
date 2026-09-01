<template>
  <div>
    <div class="page-header">
      <h2>人员管理</h2>
      <el-button type="primary" @click="openDialog()">新建人员</el-button>
    </div>

    <!-- Filters -->
    <el-card shadow="never" class="filter-bar">
      <el-form :inline="true" :model="filter" size="default">
        <el-form-item label="搜索">
          <el-input v-model="filter.keyword" placeholder="姓名/工号" clearable style="width: 180px" @change="loadData" />
        </el-form-item>
        <el-form-item label="部门">
          <el-select v-model="filter.department" placeholder="全部" clearable style="width: 150px" @change="loadData">
            <el-option v-for="dept in departmentOptions" :key="dept" :label="dept" :value="dept" />
          </el-select>
        </el-form-item>
        <el-form-item label="状态">
          <el-select v-model="filter.status" placeholder="全部" clearable style="width: 120px" @change="loadData">
            <el-option label="在职" value="active" />
            <el-option label="离职" value="resigned" />
            <el-option label="停用" value="suspended" />
          </el-select>
        </el-form-item>
        <el-form-item>
          <el-button type="primary" @click="loadData">查询</el-button>
          <el-button @click="resetFilter">重置</el-button>
        </el-form-item>
      </el-form>
    </el-card>

    <!-- Table -->
    <el-card shadow="never">
      <el-table :data="tableData" stripe v-loading="loading">
        <el-table-column prop="name" label="姓名" width="100" />
        <el-table-column prop="employee_id" label="工号" width="120" />
        <el-table-column prop="department" label="部门" width="120" />
        <el-table-column prop="position" label="职位" width="120" />
        <el-table-column prop="email" label="邮箱" width="180" show-overflow-tooltip />
        <el-table-column prop="phone" label="手机" width="130" />
        <el-table-column prop="status" label="状态" width="80" align="center">
          <template #default="{ row }">
            <el-tag :type="statusType(row.status)" size="small">{{ statusLabel(row.status) }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="entry_date" label="入职日期" width="110" />
        <el-table-column label="操作" width="350" fixed="right">
          <template #default="{ row }">
            <el-button type="primary" link size="small" @click="openDialog(row)">编辑</el-button>
            <el-button type="success" link size="small" @click="openBindAccount(row)">绑定账号</el-button>
            <el-button type="info" link size="small" @click="viewAccounts(row)">查看账号</el-button>
            <el-button v-if="row.status === 'active'" type="warning" link size="small" @click="openResign(row)">离职处理</el-button>
            <el-button type="danger" link size="small" @click="handleDelete(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
      <div class="pagination-wrap">
        <el-pagination
          v-model:current-page="pagination.page"
          v-model:page-size="pagination.page_size"
          :total="total"
          :page-sizes="[10, 20, 50]"
          layout="total, sizes, prev, pager, next"
          @size-change="loadData"
          @current-change="loadData"
        />
      </div>
    </el-card>

    <!-- Create/Edit Dialog -->
    <el-dialog v-model="dialogVisible" :title="isEdit ? '编辑人员' : '新建人员'" width="600px" destroy-on-close>
      <el-form ref="formRef" :model="form" :rules="rules" label-width="80px">
        <el-row :gutter="16">
          <el-col :span="12">
            <el-form-item label="姓名" prop="name">
              <el-input v-model="form.name" />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="工号" prop="employee_id">
              <el-input v-model="form.employee_id" :disabled="isEdit" />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="部门" prop="department">
              <el-input v-model="form.department" />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="职位" prop="position">
              <el-input v-model="form.position" />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="邮箱">
              <el-input v-model="form.email" />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="手机">
              <el-input v-model="form.phone" />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="入职日期">
              <el-date-picker v-model="form.entry_date" type="date" value-format="YYYY-MM-DD" style="width: 100%" />
            </el-form-item>
          </el-col>
          <el-col :span="12">
            <el-form-item label="状态">
              <el-select v-model="form.status" style="width: 100%">
                <el-option label="在职" value="active" />
                <el-option label="停用" value="suspended" />
              </el-select>
            </el-form-item>
          </el-col>
          <el-col :span="24">
            <el-form-item label="备注">
              <el-input v-model="form.remark" type="textarea" :rows="2" />
            </el-form-item>
          </el-col>
        </el-row>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="submitting" @click="handleSubmit">确定</el-button>
      </template>
    </el-dialog>

    <!-- Resign Dialog -->
    <el-dialog v-model="resignVisible" title="离职处理" width="500px" destroy-on-close>
      <el-alert title="离职处理将自动解绑账号并撤销权限，此操作不可撤销" type="warning" :closable="false" style="margin-bottom: 16px" />
      <el-form :model="resignForm" label-width="120px">
        <el-form-item label="离职日期">
          <el-date-picker v-model="resignForm.resign_date" type="date" value-format="YYYY-MM-DD" style="width: 100%" />
        </el-form-item>
        <el-form-item label="禁用关联账号">
          <el-switch v-model="resignForm.disable_accounts" />
        </el-form-item>
        <el-form-item label="撤销所有权限">
          <el-switch v-model="resignForm.revoke_all_permissions" />
        </el-form-item>
        <el-form-item label="备注">
          <el-input v-model="resignForm.remark" type="textarea" :rows="2" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="resignVisible = false">取消</el-button>
        <el-button type="danger" :loading="submitting" @click="handleResign">确认离职处理</el-button>
      </template>
    </el-dialog>

    <!-- Accounts Dialog -->
    <el-dialog v-model="accountsVisible" title="人员关联账号" width="700px" destroy-on-close>
      <el-table :data="personnelAccounts" stripe size="small">
        <el-table-column prop="username" label="账号" />
        <el-table-column prop="system_name" label="所属系统" />
        <el-table-column prop="bind_type" label="绑定类型" width="100" />
        <el-table-column prop="bind_status" label="状态" width="80">
          <template #default="{ row }">
            <el-tag :type="row.bind_status === 'active' ? 'success' : 'info'" size="small">
              {{ row.bind_status === 'active' ? '有效' : '已解绑' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="bind_date" label="绑定日期" width="110" />
      </el-table>
      <el-empty v-if="!personnelAccounts.length" description="暂无关联账号" />
    </el-dialog>

    <!-- Bind Account Dialog -->
    <el-dialog v-model="bindAccountVisible" title="绑定账号" width="500px" destroy-on-close>
      <el-form :model="bindForm" label-width="80px">
        <el-form-item label="选择账号">
          <el-select v-model="bindForm.account_id" filterable placeholder="搜索账号" style="width: 100%">
            <el-option
              v-for="a in accountOptions"
              :key="a.id"
              :label="`${a.username} (${a.system_name})`"
              :value="a.id"
            />
          </el-select>
        </el-form-item>
        <el-form-item label="绑定类型">
          <el-select v-model="bindForm.bind_type" style="width: 100%">
            <el-option label="主要" value="primary" />
            <el-option label="次要" value="secondary" />
            <el-option label="临时" value="temporary" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="bindAccountVisible = false">取消</el-button>
        <el-button type="primary" :loading="submitting" @click="handleBindAccount">绑定</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { personnelApi, accountsApi, relationsApi, dashboardApi } from '../../api'

const loading = ref(false)
const submitting = ref(false)
const tableData = ref<any[]>([])
const total = ref(0)
const dialogVisible = ref(false)
const resignVisible = ref(false)
const accountsVisible = ref(false)
const bindAccountVisible = ref(false)
const isEdit = ref(false)
const personnelAccounts = ref<any[]>([])
const editId = ref(0)
const accountOptions = ref<any[]>([])
const departmentOptions = ref<string[]>([])
const bindForm = reactive({ account_id: null as any, bind_type: 'primary' })

const filter = reactive({ keyword: '', department: '', status: '' })
const pagination = reactive({ page: 1, page_size: 20 })

const form = reactive({
  name: '', employee_id: '', department: '', position: '',
  email: '', phone: '', entry_date: '', status: 'active', remark: '',
})

const resignForm = reactive({
  resign_date: '', disable_accounts: true, revoke_all_permissions: true, remark: '',
})

const rules = {
  name: [{ required: true, message: '请输入姓名', trigger: 'blur' }],
  employee_id: [{ required: true, message: '请输入工号', trigger: 'blur' }],
}

const statusLabel = (s: string) => ({ active: '在职', resigned: '离职', suspended: '停用' }[s] || s)
const statusType = (s: string) => ({ active: 'success', resigned: 'danger', suspended: 'warning' }[s] || '') as any

const loadData = async () => {
  loading.value = true
  try {
    const res: any = await personnelApi.list({ ...filter, ...pagination })
    tableData.value = res.data?.items || []
    total.value = res.data?.total || 0
  } catch (e) {} finally { loading.value = false }
}

const resetFilter = () => {
  filter.keyword = ''
  filter.department = ''
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
    Object.assign(form, { name: '', employee_id: '', department: '', position: '', email: '', phone: '', entry_date: '', status: 'active', remark: '' })
  }
  dialogVisible.value = true
}

const handleSubmit = async () => {
  submitting.value = true
  try {
    if (isEdit.value) {
      await personnelApi.update(editId.value, form)
    } else {
      await personnelApi.create(form)
    }
    ElMessage.success(isEdit.value ? '更新成功' : '创建成功')
    dialogVisible.value = false
    loadData()
  } catch (e) {} finally { submitting.value = false }
}

const handleDelete = async (row: any) => {
  await ElMessageBox.confirm(`确定删除人员「${row.name}」?`, '确认')
  await personnelApi.delete(row.id)
  ElMessage.success('删除成功')
  loadData()
}

const openResign = (row: any) => {
  editId.value = row.id
  Object.assign(resignForm, { resign_date: new Date().toISOString().slice(0, 10), disable_accounts: true, revoke_all_permissions: true, remark: '' })
  resignVisible.value = true
}

const handleResign = async () => {
  if (!resignForm.resign_date) {
    ElMessage.warning('请选择离职日期')
    return
  }
  submitting.value = true
  try {
    await personnelApi.resign(editId.value, resignForm)
    ElMessage.success('离职处理完成')
    resignVisible.value = false
    loadData()
  } catch (e) {} finally { submitting.value = false }
}

const viewAccounts = async (row: any) => {
  try {
    const res: any = await personnelApi.getAccounts(row.id)
    personnelAccounts.value = res.data || []
    accountsVisible.value = true
  } catch (e) {}
}

const openBindAccount = async (row: any) => {
  editId.value = row.id
  bindForm.account_id = null
  bindForm.bind_type = 'primary'
  // Load available accounts
  try {
    const res: any = await accountsApi.list({ page: 1, page_size: 200 })
    accountOptions.value = res.data?.items || []
  } catch (e) {}
  bindAccountVisible.value = true
}

const handleBindAccount = async () => {
  if (!bindForm.account_id) {
    ElMessage.warning('请选择账号')
    return
  }
  submitting.value = true
  try {
    await relationsApi.bindAccount({
      personnel_id: editId.value,
      account_id: bindForm.account_id,
      bind_type: bindForm.bind_type,
    })
    ElMessage.success('绑定成功')
    bindAccountVisible.value = false
  } catch (e) {} finally { submitting.value = false }
}

const loadDepartments = async () => {
  try {
    const res: any = await dashboardApi.departments()
    departmentOptions.value = res.data || []
  } catch (e) {}
}

onMounted(() => {
  loadData()
  loadDepartments()
})
</script>
