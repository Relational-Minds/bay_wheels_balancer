import { Truck, CheckCircle, Clock, MapPin } from 'lucide-react';

const activeTasks = [
  {
    id: 'T-1847',
    type: 'rebalance',
    from: 'Berry St at 4th St',
    to: 'Market St at 10th St',
    bikes: 10,
    crew: 'Crew A',
    status: 'in_progress',
    progress: 65,
    eta: '8 min',
    priority: 'high'
  },
  {
    id: 'T-1848',
    type: 'rebalance',
    from: 'Grant Ave at Columbus',
    to: 'San Francisco Caltrain',
    bikes: 12,
    crew: 'Crew B',
    status: 'in_progress',
    progress: 40,
    eta: '12 min',
    priority: 'high'
  },
  {
    id: 'T-1849',
    type: 'rebalance',
    from: 'Jackson St at Drumm St',
    to: 'Steuart St at Market',
    bikes: 8,
    crew: 'Crew C',
    status: 'assigned',
    progress: 10,
    eta: '22 min',
    priority: 'medium'
  },
  {
    id: 'T-1846',
    type: 'rebalance',
    from: 'Townsend St at 7th St',
    to: 'Washington St at Kearny',
    bikes: 7,
    crew: 'Crew A',
    status: 'completed',
    progress: 100,
    eta: 'Done',
    priority: 'medium'
  }
];

export function ActiveTasksPanel() {
  const getStatusColor = (status: string) => {
    switch (status) {
      case 'in_progress': return 'bg-blue-100 text-blue-700';
      case 'assigned': return 'bg-yellow-100 text-yellow-700';
      case 'completed': return 'bg-green-100 text-green-700';
      default: return 'bg-gray-100 text-gray-700';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'in_progress': return <Truck className="w-4 h-4" />;
      case 'assigned': return <Clock className="w-4 h-4" />;
      case 'completed': return <CheckCircle className="w-4 h-4" />;
      default: return null;
    }
  };

  const getPriorityColor = (priority: string) => {
    switch (priority) {
      case 'high': return 'border-l-red-500';
      case 'medium': return 'border-l-yellow-500';
      case 'low': return 'border-l-green-500';
      default: return 'border-l-gray-300';
    }
  };

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200">
      {/* Header */}
      <div className="px-4 py-3 border-b border-gray-200 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Truck className="w-5 h-5 text-blue-600" />
          <h2 className="text-gray-900">Active Rebalancing Tasks</h2>
          <span className="px-2 py-0.5 bg-blue-100 text-blue-700 rounded-full text-xs">
            {activeTasks.filter(t => t.status !== 'completed').length} active
          </span>
        </div>
        <p className="text-sm text-gray-600">Current assignments and crew locations</p>
      </div>

      {/* Tasks List */}
      <div className="p-4 space-y-3">
        {activeTasks.map((task) => (
          <div 
            key={task.id} 
            className={`border-l-4 ${getPriorityColor(task.priority)} bg-gray-50 rounded-r-lg p-4 hover:shadow-md transition-shadow`}
          >
            <div className="flex items-start justify-between mb-3">
              <div className="flex-1">
                <div className="flex items-center gap-2 mb-2">
                  <span className="text-sm text-gray-900">{task.id}</span>
                  <span className={`px-2 py-0.5 rounded-full text-xs flex items-center gap-1 ${getStatusColor(task.status)}`}>
                    {getStatusIcon(task.status)}
                    {task.status.replace('_', ' ')}
                  </span>
                  <span className="text-xs text-gray-500">• {task.crew}</span>
                </div>
                
                <div className="flex items-center gap-3 text-sm">
                  <div className="flex items-center gap-1.5">
                    <MapPin className="w-4 h-4 text-blue-600" />
                    <span className="text-gray-700">{task.from}</span>
                  </div>
                  <span className="text-gray-400">→</span>
                  <div className="flex items-center gap-1.5">
                    <MapPin className="w-4 h-4 text-green-600" />
                    <span className="text-gray-700">{task.to}</span>
                  </div>
                </div>
              </div>

              <div className="text-right ml-4">
                <div className="text-sm text-gray-900 mb-1">{task.bikes} bikes</div>
                <div className="text-xs text-gray-600">ETA: {task.eta}</div>
              </div>
            </div>

            {/* Progress Bar */}
            <div className="flex items-center gap-2">
              <div className="flex-1 bg-gray-200 rounded-full h-2">
                <div 
                  className={`h-2 rounded-full transition-all ${
                    task.status === 'completed' ? 'bg-green-500' : 'bg-blue-500'
                  }`}
                  style={{ width: `${task.progress}%` }}
                ></div>
              </div>
              <span className="text-xs text-gray-600 w-10 text-right">{task.progress}%</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
