import { TrendingDown, Clock, RefreshCw, Zap, BarChart3 } from 'lucide-react';

const kpis = [
  {
    label: 'System Stockout Rate',
    value: '4.2%',
    change: '-1.3%',
    trend: 'down',
    icon: BarChart3,
    color: 'blue',
    description: 'Stations empty/full in last hour'
  },
  {
    label: 'Avg Task Time',
    value: '18.5 min',
    change: '-2.1 min',
    trend: 'down',
    icon: Clock,
    color: 'green',
    description: 'Average rebalancing task duration'
  },
  {
    label: 'Task Retry Rate',
    value: '2.1%',
    change: '+0.3%',
    trend: 'up',
    icon: RefreshCw,
    color: 'yellow',
    description: 'Tasks requiring reassignment'
  },
  {
    label: 'API Latency',
    value: '127 ms',
    change: '-15 ms',
    trend: 'down',
    icon: Zap,
    color: 'purple',
    description: 'GBFS feed response time'
  }
];

export function KPISummary() {
  const getColorClasses = (color: string) => {
    switch (color) {
      case 'blue': return 'bg-blue-50 text-blue-600';
      case 'green': return 'bg-green-50 text-green-600';
      case 'yellow': return 'bg-yellow-50 text-yellow-600';
      case 'purple': return 'bg-purple-50 text-purple-600';
      default: return 'bg-gray-50 text-gray-600';
    }
  };

  return (
    <div className="grid grid-cols-4 gap-4">
      {kpis.map((kpi) => {
        const Icon = kpi.icon;
        return (
          <div key={kpi.label} className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
            <div className="flex items-start justify-between mb-3">
              <div className={`p-2 rounded-lg ${getColorClasses(kpi.color)}`}>
                <Icon className="w-5 h-5" />
              </div>
              <div className={`flex items-center gap-1 text-xs px-2 py-0.5 rounded-full ${
                kpi.trend === 'down' ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'
              }`}>
                <TrendingDown className={`w-3 h-3 ${kpi.trend === 'up' ? 'rotate-180' : ''}`} />
                <span>{kpi.change}</span>
              </div>
            </div>
            <div>
              <p className="text-2xl text-gray-900 mb-1">{kpi.value}</p>
              <p className="text-sm text-gray-600 mb-0.5">{kpi.label}</p>
              <p className="text-xs text-gray-500">{kpi.description}</p>
            </div>
          </div>
        );
      })}
    </div>
  );
}
