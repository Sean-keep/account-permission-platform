<template>
  <div>
    <div class="page-header">
      <h2>系统台账</h2>
    </div>

    <!-- System Selector -->
    <el-card shadow="never" style="margin-bottom: 16px">
      <el-form :inline="true" size="default">
        <el-form-item label="选择系统">
          <el-select
            v-model="selectedSystemId"
            filterable
            placeholder="选择系统"
            style="width: 300px"
            @change="loadSystemPersonnel"
          >
            <el-option
              v-for="s in systemOptions"
              :key="s.id"
              :label="s.name"
              :value="s.id"
            />
          </el-select>
        </el-form-item>
      </el-form>
    </el-card>

    <!-- System Info -->
    <el-row :gutter="16" v-if="systemInfo" style="margin-bottom: 16px; display: flex; align-items: stretch">
      <el-col :span="6">
        <el-card shadow="hover">
          <div class="info-item"><span class="label">系统名称：</span>{{ systemInfo.name }}</div>
          <div class="info-item"><span class="label">地址：</span>{{ systemInfo.url || '-' }}</div>
          <div class="info-item"><span class="label">分类：</span>{{ systemInfo.category || '-' }}</div>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="hover">
          <div class="info-item"><span class="label">负责人：</span>{{ systemInfo.owner || '-' }}</div>
          <div class="info-item"><span class="label">状态：</span>
            <span :style="{ color: systemInfo.status === 'active' ? '#67c23a' : '#909399' }">
              {{ systemInfo.status === 'active' ? '● 启用' : '○ 停用' }}
            </span>
          </div>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="hover" class="stat-card-compact">
          <div class="stat-number-compact">{{ uniquePersonnel.length }}</div>
          <div class="stat-label-compact">关联人员数</div>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="hover" class="stat-card-compact">
          <div class="stat-number-compact" style="color: #67c23a">{{ personnelList.length }}</div>
          <div class="stat-label-compact">关联账号数</div>
        </el-card>
      </el-col>
    </el-row>

    <!-- Personnel Table -->
    <el-card shadow="never">
      <template #header>
        <span>系统关联人员列表</span>
      </template>
      <el-table :data="personnelList" stripe v-loading="loading" style="width: 100%">
        <el-table-column prop="name" label="姓名" />
        <el-table-column prop="employee_id" label="工号" />
        <el-table-column prop="department" label="部门" />
        <el-table-column prop="position" label="职位" />
        <el-table-column prop="username" label="账号" />
        <el-table-column prop="account_type" label="账号类型">
          <template #default="{ row }">
            {{ typeLabel(row.account_type) }}
          </template>
        </el-table-column>
        <el-table-column prop="bind_type" label="绑定类型">
          <template #default="{ row }">
            <el-tag size="small" :type="bindTypeTag(row.bind_type)">{{ bindTypeLabel(row.bind_type) }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="status" label="人员状态">
          <template #default="{ row }">
            <el-tag :type="row.status === 'active' ? 'success' : 'danger'" size="small">
              {{ row.status === 'active' ? '在职' : '离职' }}
            </el-tag>
          </template>
        </el-table-column>
      </el-table>
      <el-empty v-if="!personnelList.length && systemInfo" description="该系统暂无关联人员" />
      <el-empty v-if="!systemInfo" description="请先选择系统" />
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { systemsApi } from '../../api'

const loading = ref(false)
const selectedSystemId = ref<number | null>(null)
const systemOptions = ref<any[]>([])
const systemInfo = ref<any>(null)
const personnelList = ref<any[]>([])

const uniquePersonnel = computed(() => {
  const ids = new Set(personnelList.value.map(p => p.personnel_id))
  return Array.from(ids)
})

const typeLabel = (t: string) => ({ normal: '普通', admin: '管理员', service: '服务账号', shared: '共享' }[t] || t)
const bindTypeLabel = (t: string) => ({ primary: '主要', secondary: '次要', temporary: '临时' }[t] || t)
const bindTypeTag = (t: string) => ({ primary: '', secondary: 'warning', temporary: 'info' }[t] || '') as any

const loadSystemPersonnel = async () => {
  if (!selectedSystemId.value) return
  loading.value = true
  try {
    const res: any = await systemsApi.getPersonnel(selectedSystemId.value)
    systemInfo.value = res.data?.system
    personnelList.value = res.data?.personnel || []
  } catch (e) {} finally { loading.value = false }
}

onMounted(async () => {
  try {
    const res: any = await systemsApi.allList()
    systemOptions.value = res.data || []
  } catch (e) {}
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
