<template>
  <div>
    <div class="page-header">
      <h2>系统管理</h2>
      <el-button type="primary" @click="openDialog()">新建系统</el-button>
    </div>

    <el-card shadow="never" class="filter-bar">
      <el-form :inline="true" :model="filter" size="default">
        <el-form-item label="搜索">
          <el-input v-model="filter.keyword" placeholder="系统名称" clearable style="width: 180px" @change="loadData" />
        </el-form-item>
        <el-form-item>
          <el-button type="primary" @click="loadData">查询</el-button>
          <el-button @click="filter.keyword = ''; loadData()">重置</el-button>
        </el-form-item>
      </el-form>
    </el-card>

    <el-card shadow="never">
      <el-table :data="tableData" stripe v-loading="loading">
        <el-table-column prop="name" label="系统名称" width="150" />
        <el-table-column prop="category" label="分类" width="100" />
        <el-table-column prop="owner" label="负责人" width="100" />
        <el-table-column prop="url" label="地址" show-overflow-tooltip />
        <el-table-column prop="status" label="状态" width="80" align="center">
          <template #default="{ row }">
            <el-tag :type="row.status === 'active' ? 'success' : 'info'" size="small">
              {{ row.status === 'active' ? '启用' : '停用' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="220" fixed="right">
          <template #default="{ row }">
            <el-button type="primary" link size="small" @click="openDialog(row)">编辑</el-button>
            <el-button type="success" link size="small" @click="viewPersonnel(row)">查看人员</el-button>
            <el-button type="danger" link size="small" @click="handleDelete(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
      <div class="pagination-wrap">
        <el-pagination v-model:current-page="pagination.page" v-model:page-size="pagination.page_size" :total="total" :page-sizes="[10, 20, 50]" layout="total, sizes, prev, pager, next" @size-change="loadData" @current-change="loadData" />
      </div>
    </el-card>

    <!-- Dialog -->
    <el-dialog v-model="dialogVisible" :title="isEdit ? '编辑系统' : '新建系统'" width="550px" destroy-on-close>
      <el-form ref="formRef" :model="form" :rules="rules" label-width="80px">
        <el-form-item label="名称" prop="name">
          <el-input v-model="form.name" />
        </el-form-item>
        <el-form-item label="分类">
          <el-select v-model="form.category" filterable allow-create placeholder="选择或输入" style="width: 100%">
            <el-option label="办公" value="办公" />
            <el-option label="财务" value="财务" />
            <el-option label="运维" value="运维" />
            <el-option label="开发" value="开发" />
            <el-option label="安全" value="安全" />
            <el-option label="HR" value="HR" />
          </el-select>
        </el-form-item>
        <el-form-item label="负责人">
          <el-input v-model="form.owner" />
        </el-form-item>
        <el-form-item label="地址">
          <el-input v-model="form.url" placeholder="系统访问地址" />
        </el-form-item>
        <el-form-item label="描述">
          <el-input v-model="form.description" type="textarea" :rows="2" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="submitting" @click="handleSubmit">确定</el-button>
      </template>
    </el-dialog>

    <!-- Personnel Dialog -->
    <el-dialog v-model="personnelVisible" :title="`${currentSystem} - 关联人员`" width="800px" destroy-on-close>
      <el-table :data="systemPersonnel" stripe size="small">
        <el-table-column prop="name" label="姓名" width="100" />
        <el-table-column prop="employee_id" label="工号" width="100" />
        <el-table-column prop="department" label="部门" width="100" />
        <el-table-column prop="position" label="职位" width="120" />
        <el-table-column prop="username" label="账号" width="120" />
        <el-table-column prop="account_type" label="账号类型" width="100">
          <template #default="{ row }">
            {{ typeLabel(row.account_type) }}
          </template>
        </el-table-column>
        <el-table-column prop="bind_type" label="绑定类型" width="100" />
        <el-table-column prop="status" label="状态" width="80">
          <template #default="{ row }">
            <el-tag :type="row.status === 'active' ? 'success' : 'info'" size="small">
              {{ row.status === 'active' ? '在职' : '离职' }}
            </el-tag>
          </template>
        </el-table-column>
      </el-table>
      <el-empty v-if="!systemPersonnel.length" description="暂无关联人员" />
      <div style="margin-top: 12px; color: #909399; font-size: 14px">
        共 <strong>{{ systemPersonnel.length }}</strong> 个人员有关联账号
      </div>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { systemsApi } from '../../api'

const loading = ref(false)
const submitting = ref(false)
const tableData = ref<any[]>([])
const total = ref(0)
const dialogVisible = ref(false)
const personnelVisible = ref(false)
const isEdit = ref(false)
const editId = ref(0)
const currentSystem = ref('')
const systemPersonnel = ref<any[]>([])

const filter = reactive({ keyword: '' })
const pagination = reactive({ page: 1, page_size: 20 })
const form = reactive({ name: '', category: '', owner: '', url: '', description: '', status: 'active' })

const rules = {
  name: [{ required: true, message: '请输入系统名称', trigger: 'blur' }],
}

const loadData = async () => {
  loading.value = true
  try {
    const res: any = await systemsApi.list({ ...filter, ...pagination })
    tableData.value = res.data?.items || []
    total.value = res.data?.total || 0
  } catch (e) {} finally { loading.value = false }
}

const openDialog = (row?: any) => {
  isEdit.value = !!row
  if (row) {
    editId.value = row.id
    Object.assign(form, row)
  } else {
    editId.value = 0
    Object.assign(form, { name: '', category: '', owner: '', url: '', description: '', status: 'active' })
  }
  dialogVisible.value = true
}

const handleSubmit = async () => {
  submitting.value = true
  try {
    if (isEdit.value) {
      await systemsApi.update(editId.value, form)
    } else {
      await systemsApi.create(form)
    }
    ElMessage.success(isEdit.value ? '更新成功' : '创建成功')
    dialogVisible.value = false
    loadData()
  } catch (e) {} finally { submitting.value = false }
}

const handleDelete = async (row: any) => {
  await ElMessageBox.confirm(`确定删除系统「${row.name}」?`, '确认')
  await systemsApi.delete(row.id)
  ElMessage.success('删除成功')
  loadData()
}

const typeLabel = (t: string) => ({ normal: '普通', admin: '管理员', service: '服务账号', shared: '共享' }[t] || t)

const viewPersonnel = async (row: any) => {
  currentSystem.value = row.name
  try {
    const res: any = await systemsApi.getPersonnel(row.id)
    systemPersonnel.value = res.data?.personnel || []
    personnelVisible.value = true
  } catch (e) {}
}

onMounted(loadData)
</script>
