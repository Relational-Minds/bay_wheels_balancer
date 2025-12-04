import { MapView } from './components/MapView';
import { CriticalStationsTable } from './components/CriticalStationsTable';
import { ActiveTasksPanel } from './components/ActiveTasksPanel';
import { TrendCharts } from './components/TrendCharts';
import { KPISummary } from './components/KPISummary';
import { Activity } from 'lucide-react';

export default function App() {
  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white border-b border-gray-200 px-6 py-4">
        <div className="flex items-center gap-3">
          <div className="bg-blue-600 p-2 rounded-lg">
            <Activity className="w-6 h-6 text-white" />
          </div>
          <div>
            <h1 className="text-gray-900">Bay Wheels Station Balancer</h1>
            <p className="text-gray-600 text-sm">Real-time Operations Command Center</p>
          </div>
          <div className="ml-auto flex items-center gap-4">
            <div className="text-right">
              <p className="text-sm text-gray-600">Last Updated</p>
              <p className="text-sm text-gray-900">{new Date().toLocaleTimeString()}</p>
            </div>
            <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
            <span className="text-sm text-gray-600">Live</span>
          </div>
        </div>
      </header>

      {/* Main Dashboard Layout */}
      <div className="p-6 h-[calc(100vh-88px)]">
        <div className="grid grid-cols-12 gap-6 h-full">
          {/* Left Side - Map View (40% width) */}
          <div className="col-span-5 h-full">
            <MapView />
          </div>

          {/* Right Side - Dashboard Panels (60% width) */}
          <div className="col-span-7 flex flex-col gap-6 h-full overflow-auto">
            {/* KPI Summary */}
            <KPISummary />

            {/* Critical Stations Table */}
            <CriticalStationsTable />

            {/* Active Rebalancing Tasks */}
            <ActiveTasksPanel />

            {/* Trend Charts */}
            <TrendCharts />
          </div>
        </div>
      </div>
    </div>
  );
}
