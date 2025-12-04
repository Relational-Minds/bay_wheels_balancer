import { AlertTriangle, TrendingUp, TrendingDown } from 'lucide-react';

const criticalStations = [
  { 
    id: 1, 
    name: 'Market St at 10th St', 
    status: 'empty', 
    current: 3, 
    capacity: 35, 
    prediction: 'Empty in 12 min',
    score: 9.2,
    trend: 'down'
  },
  { 
    id: 2, 
    name: 'Berry St at 4th St', 
    status: 'full', 
    current: 22, 
    capacity: 23, 
    prediction: 'Full in 8 min',
    score: 8.8,
    trend: 'up'
  },
  { 
    id: 5, 
    name: 'Steuart St at Market St', 
    status: 'empty', 
    current: 2, 
    capacity: 23, 
    prediction: 'Empty in 15 min',
    score: 8.5,
    trend: 'down'
  },
  { 
    id: 8, 
    name: 'San Francisco Caltrain', 
    status: 'empty', 
    current: 1, 
    capacity: 27, 
    prediction: 'Empty in 5 min',
    score: 9.5,
    trend: 'down'
  },
  { 
    id: 12, 
    name: 'Washington St at Kearny St', 
    status: 'empty', 
    current: 2, 
    capacity: 15, 
    prediction: 'Empty in 18 min',
    score: 7.9,
    trend: 'down'
  },
];

export function CriticalStationsTable() {
  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200">
      {/* Header */}
      <div className="px-4 py-3 border-b border-gray-200 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <AlertTriangle className="w-5 h-5 text-red-600" />
          <h2 className="text-gray-900">Critical Stations</h2>
          <span className="px-2 py-0.5 bg-red-100 text-red-700 rounded-full text-xs">
            {criticalStations.length} stations
          </span>
        </div>
        <p className="text-sm text-gray-600">Predicted to run empty/full soon</p>
      </div>

      {/* Table */}
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="px-4 py-3 text-left text-xs text-gray-600">Station Name</th>
              <th className="px-4 py-3 text-left text-xs text-gray-600">Status</th>
              <th className="px-4 py-3 text-left text-xs text-gray-600">Current / Capacity</th>
              <th className="px-4 py-3 text-left text-xs text-gray-600">Prediction</th>
              <th className="px-4 py-3 text-left text-xs text-gray-600">Risk Score</th>
              <th className="px-4 py-3 text-left text-xs text-gray-600">Trend</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {criticalStations.map((station) => (
              <tr key={station.id} className="hover:bg-gray-50 transition-colors">
                <td className="px-4 py-3 text-sm text-gray-900">{station.name}</td>
                <td className="px-4 py-3">
                  <span className={`px-2 py-1 rounded-full text-xs ${
                    station.status === 'empty' 
                      ? 'bg-red-100 text-red-700' 
                      : 'bg-orange-100 text-orange-700'
                  }`}>
                    {station.status === 'empty' ? '⚠️ Running Empty' : '⚠️ Nearly Full'}
                  </span>
                </td>
                <td className="px-4 py-3 text-sm text-gray-900">
                  <span className={station.current <= 3 || station.current >= station.capacity - 2 ? 'text-red-600' : ''}>
                    {station.current}
                  </span>
                  {' / '}{station.capacity}
                </td>
                <td className="px-4 py-3 text-sm text-gray-900">{station.prediction}</td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <span className="text-sm text-gray-900">{station.score}</span>
                    <div className="flex-1 bg-gray-200 rounded-full h-1.5 w-16">
                      <div 
                        className="bg-red-500 h-1.5 rounded-full"
                        style={{ width: `${station.score * 10}%` }}
                      ></div>
                    </div>
                  </div>
                </td>
                <td className="px-4 py-3">
                  {station.trend === 'down' ? (
                    <TrendingDown className="w-4 h-4 text-red-500" />
                  ) : (
                    <TrendingUp className="w-4 h-4 text-orange-500" />
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
