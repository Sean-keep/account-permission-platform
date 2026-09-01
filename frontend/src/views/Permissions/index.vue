<template>
  <div>
    <div class="page-header">
      <h2>权限管理</h2>
      <el-button type="primary" @click="openDialog()">新建权限</el-button>
    </div>

    <el-card shadow="never" class="filter-bar">
      <el-form :inline="true" :model="filter" size="default">
        <el-form-item label="搜索">
          <el-input v-model="filter.keyword" placeholder="权限名称/编码" clearable style="width: 180px" @change="loadData" />
        </el-form-item>
        <el-form-item label="系统">
          <el-select v-model="filter.system_id" placeholder="全部" clearable style="width: 150px" @change="loadData">
            <el-option v-for="s in systemOptions" :key="s.id" :label="s.name" :value="s.id" />
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
        <el-table-column prop="name" label="权限名称" width="180" />
        <el-table-column prop="code" label="权限编码" width="180" />
        <el-table-column prop="system_name" label="所属系统" width="120" />
        <el-table-column prop="category" label="分类" width="100" />
        <el-table-column prop="description" label="描述" show-overflow-tooltip />
        <el-table-column label="操作" width="150" fixed="right">
          <template #default="{ row }">
            <el-button type="primary" link size="small" @click="openDialog(row)">编辑</el-button>
            <el-button type="danger" link size="small" @click="handleDelete(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
      <div class="pagination-wrap">
        <el-pagination v-model:current-page="pagination.page" v-model:page-size="pagination.page_size" :total="total" :page-sizes="[10, 20, 50]" layout="total, sizes, prev, pager, next" @size-change="loadData" @current-change="loadData" />
      </div>
    </el-card>

    <!-- Dialog -->
    <el-dialog v-model="dialogVisible" :title="isEdit ? '编辑权限' : '新建权限'" width="500px" destroy-on-close>
      <el-form ref="formRef" :model="form" :rules="rules" label-width="80px">
        <el-form-item label="名称" prop="name">
          <el-input v-model="form.name" />
        </el-form-item>
        <el-form-item label="编码" prop="code">
          <el-input v-model="form.code" placeholder="如 user:read, admin:write" />
        </el-form-item>
        <el-form-item label="所属系统" prop="system_id">
          <el-select v-model="form.system_id" placeholder="选择系统" style="width: 100%">
            <el-option v-for="s in systemOptions" :key="s.id" :label="s.name" :value="s.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="分类">
          <el-select v-model="form.category" filterable allow-create style="width: 100%">
            <el-option label="功能权限" value="功能权限" />
            <el-option label="数据权限" value="数据权限" />
            <el-option label="角色" value="角色" />
            <el-option label="菜单权限" value="菜单权限" />
          </el-select>
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
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, onMounted } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { permissionsApi, systemsApi } from '../../api'

const loading = ref(false)
const submitting = ref(false)
const tableData = ref<any[]>([])
const total = ref(0)
const dialogVisible = ref(false)
const isEdit = ref(false)
const editId = ref(0)
const systemOptions = ref<any[]>([])

const filter = reactive({ keyword: '', system_id: 0 })
const pagination = reactive({ page: 1, page_size: 20 })
const form = reactive({ name: '', code: '', system_id: null as any, category: '', description: '' })

const rules = {
  name: [{ required: true, message: '请输入权限名称', trigger: 'blur' }],
  code: [{ required: true, message: '请输入权限编码', trigger: 'blur' }],
  system_id: [{ required: true, message: '请选择所属系统', trigger: 'change' }],
}

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
    const res: any = await permissionsApi.list(params)
    tableData.value = res.data?.items || []
    total.value = res.data?.total || 0
  } catch (e) {} finally { loading.value = false }
}

const resetFilter = () => {
  filter.keyword = ''
  filter.system_id = 0
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
    Object.assign(form, { name: '', code: '', system_id: null, category: '', description: '' })
  }
  dialogVisible.value = true
}

const handleSubmit = async () => {
  submitting.value = true
  try {
    if (isEdit.value) {
      await permissionsApi.update(editId.value, form)
    } else {
      await permissionsApi.create(form)
    }
    ElMessage.success(isEdit.value ? '更新成功' : '创建成功')
    dialogVisible.value = false
    loadData()
  } catch (e) {} finally { submitting.value = false }
}

const handleDelete = async (row: any) => {
  await ElMessageBox.confirm(`确定删除权限「${row.name}」?`, '确认')
  await permissionsApi.delete(row.id)
  ElMessage.success('删除成功')
  loadData()
}

onMounted(() => {
  loadSystems()
  loadData()
})
</script>
