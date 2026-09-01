<template>
  <div>
    <!-- Stats Cards -->
    <el-row :gutter="16" style="margin-bottom: 20px">
      <el-col :span="6">
        <el-card shadow="hover" class="stat-card">
          <div class="stat-icon" style="background: #409eff">
            <el-icon size="28"><User /></el-icon>
          </div>
          <div class="stat-content">
            <div class="stat-number">{{ stats.personnel?.active || 0 }}</div>
            <div class="stat-label">在职人员</div>
          </div>
          <div class="stat-footer">
            共 {{ stats.personnel?.total || 0 }} 人
            <span v-if="stats.personnel?.resigned" style="color: #f56c6c; margin-left: 8px">
              离职 {{ stats.personnel.resigned }} 人
            </span>
          </div>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="hover" class="stat-card">
          <div class="stat-icon" style="background: #67c23a">
            <el-icon size="28"><Monitor /></el-icon>
          </div>
          <div class="stat-content">
            <div class="stat-number" style="color: #67c23a">{{ stats.systems?.active || 0 }}</div>
            <div class="stat-label">业务系统</div>
          </div>
          <div class="stat-footer">
            已接入 {{ stats.systems?.active || 0 }} 个系统
          </div>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="hover" class="stat-card">
          <div class="stat-icon" style="background: #e6a23c">
            <el-icon size="28"><Avatar /></el-icon>
          </div>
          <div class="stat-content">
            <div class="stat-number" style="color: #e6a23c">{{ stats.accounts?.active || 0 }}</div>
            <div class="stat-label">活跃账号</div>
          </div>
          <div class="stat-footer">
            <span v-if="stats.accounts?.resigned_pending" style="color: #f56c6c">
              {{ stats.accounts.resigned_pending }} 个待处理
            </span>
            <span v-else>账号状态正常</span>
          </div>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="hover" class="stat-card">
          <div class="stat-icon" style="background: #909399">
            <el-icon size="28"><Connection /></el-icon>
          </div>
          <div class="stat-content">
            <div class="stat-number" style="color: #909399">{{ stats.bindings?.personnel_account || 0 }}</div>
            <div class="stat-label">人员账号绑定</div>
          </div>
          <div class="stat-footer">
            账号权限绑定 {{ stats.bindings?.account_permission || 0 }}
          </div>
        </el-card>
      </el-col>
    </el-row>

    <!-- Recent Logs & Department Stats -->
    <el-row :gutter="16">
      <el-col :span="16">
        <el-card shadow="never">
          <template #header>
            <div class="card-header">
              <span style="font-weight: 600">最近操作记录</span>
              <el-button type="primary" link @click="$router.push('/audit-logs')">查看全部</el-button>
            </div>
          </template>
          <el-table :data="stats.recent_logs || []" stripe size="small">
            <el-table-column prop="created_at" label="时间" width="160" />
            <el-table-column prop="operator" label="操作人" width="80" />
            <el-table-column prop="action" label="操作" width="80">
              <template #default="{ row }">
                <el-tag size="small" :type="actionTagType(row.action)">{{ actionLabel(row.action) }}</el-tag>
              </template>
            </el-table-column>
            <el-table-column prop="target_type" label="对象类型" width="80">
              <template #default="{ row }">
                {{ targetTypeLabel(row.target_type) }}
              </template>
            </el-table-column>
            <el-table-column prop="target_name" label="对象" width="120" />
            <el-table-column prop="detail" label="详情" show-overflow-tooltip />
          </el-table>
        </el-card>
      </el-col>
      <el-col :span="8">
        <el-card shadow="never">
          <template #header>
            <div class="card-header">
              <span style="font-weight: 600">部门人员分布</span>
            </div>
          </template>
          <div v-if="stats.departments?.length" class="dept-list">
            <div v-for="dept in stats.departments" :key="dept.department" class="dept-item">
              <div class="dept-info">
                <span class="dept-name">{{ dept.department || '未分配' }}</span>
                <span class="dept-count">{{ dept.count }} 人</span>
              </div>
              <el-progress
                :percentage="Math.round(dept.count / (stats.personnel?.total || 1) * 100)"
                :stroke-width="8"
                :show-text="false"
              />
            </div>
          </div>
          <el-empty v-else description="暂无数据" :image-size="60" />
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { User, Monitor, Avatar, Connection } from '@element-plus/icons-vue'
import { dashboardApi } from '../../api'

const stats = ref<any>({})

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
  user: '用户',
}

const actionLabel = (action: string) => actionMap[action]?.label || action
const actionTagType = (action: string) => (actionMap[action]?.type || '') as any
const targetTypeLabel = (type: string) => targetTypeMap[type] || type

onMounted(async () => {
  try {
    const res: any = await dashboardApi.stats()
    stats.value = res.data || {}
  } catch (e) {
    // handled
  }
})
</script>

<style scoped>
.stat-card {
  position: relative;
  overflow: hidden;
}

.stat-card :deep(.el-card__body) {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  padding: 20px;
}

.stat-icon {
  width: 56px;
  height: 56px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  margin-right: 16px;
}

.stat-content {
  flex: 1;
}

.stat-number {
  font-size: 28px;
  font-weight: 700;
  color: #409eff;
  line-height: 1.2;
}

.stat-label {
  font-size: 14px;
  color: #909399;
  margin-top: 4px;
}

.stat-footer {
  width: 100%;
  font-size: 12px;
  color: #909399;
  margin-top: 12px;
  padding-top: 12px;
  border-top: 1px solid #f0f0f0;
}

.card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.dept-list {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.dept-item {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.dept-info {
  display: flex;
  justify-content: space-between;
  font-size: 13px;
}

.dept-name {
  color: #606266;
}

.dept-count {
  color: #909399;
}
</style>
