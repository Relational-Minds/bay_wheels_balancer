import {
  LineChart,
  Line,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from "recharts";
import { TrendingUp } from "lucide-react";

// Mock data for hourly stockout percentage
const stockoutData = [
  { hour: "00:00", stockout: 2.1, target: 5 },
  { hour: "02:00", stockout: 1.8, target: 5 },
  { hour: "04:00", stockout: 1.5, target: 5 },
  { hour: "06:00", stockout: 3.2, target: 5 },
  { hour: "08:00", stockout: 6.8, target: 5 },
  { hour: "10:00", stockout: 5.4, target: 5 },
  { hour: "12:00", stockout: 4.9, target: 5 },
  { hour: "14:00", stockout: 4.2, target: 5 },
  { hour: "16:00", stockout: 5.8, target: 5 },
  { hour: "18:00", stockout: 7.2, target: 5 },
  { hour: "20:00", stockout: 4.5, target: 5 },
  { hour: "22:00", stockout: 3.1, target: 5 },
];

// Mock data for bike movement trends
const movementData = [
  { hour: "00:00", pickups: 45, returns: 52 },
  { hour: "02:00", pickups: 28, returns: 31 },
  { hour: "04:00", pickups: 18, returns: 22 },
  { hour: "06:00", pickups: 89, returns: 64 },
  { hour: "08:00", pickups: 234, returns: 156 },
  { hour: "10:00", pickups: 198, returns: 187 },
  { hour: "12:00", pickups: 176, returns: 189 },
  { hour: "14:00", pickups: 165, returns: 172 },
  { hour: "16:00", pickups: 189, returns: 198 },
  { hour: "18:00", pickups: 156, returns: 245 },
  { hour: "20:00", pickups: 134, returns: 187 },
  { hour: "22:00", pickups: 87, returns: 96 },
];

export function TrendCharts() {
  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200">
      {/* Header */}
      <div className="px-4 py-3 border-b border-gray-200 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <TrendingUp className="w-5 h-5 text-blue-600" />
          <h2 className="text-gray-900">System Trends</h2>
        </div>
        <p className="text-sm text-gray-600">
          Hourly stockout % and bike movement patterns
        </p>
      </div>

      {/* Charts Grid */}
      <div className="p-4 grid grid-cols-2 gap-6">
        {/* Stockout Percentage Chart */}
        <div>
          <h3 className="text-sm text-gray-700 mb-3">
            Hourly Stockout Percentage
          </h3>
          <ResponsiveContainer width="100%" height={200}>
            <LineChart data={stockoutData}>
              <CartesianGrid
                strokeDasharray="3 3"
                stroke="#E5E7EB"
              />
              <XAxis
                dataKey="hour"
                tick={{ fontSize: 11 }}
                stroke="#9CA3AF"
              />
              <YAxis
                tick={{ fontSize: 11 }}
                stroke="#9CA3AF"
                label={{
                  value: "%",
                  angle: -90,
                  position: "insideLeft",
                  style: { fontSize: 11 },
                }}
              />
              <Tooltip
                contentStyle={{
                  fontSize: 12,
                  borderRadius: 8,
                  border: "1px solid #E5E7EB",
                }}
              />
              <Legend wrapperStyle={{ fontSize: 11 }} />
              <Line
                type="monotone"
                dataKey="stockout"
                stroke="#EF4444"
                strokeWidth={2}
                name="Stockout %"
                dot={{ fill: "#EF4444", r: 3 }}
              />
              <Line
                type="monotone"
                dataKey="target"
                stroke="#9CA3AF"
                strokeWidth={1}
                strokeDasharray="5 5"
                name="Target (5%)"
                dot={false}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>

        {/* Bike Movement Chart */}
        <div>
          <h3 className="text-sm text-gray-700 mb-3">
            Bike Movement Trends
          </h3>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={movementData}>
              <CartesianGrid
                strokeDasharray="3 3"
                stroke="#E5E7EB"
              />
              <XAxis
                dataKey="hour"
                tick={{ fontSize: 11 }}
                stroke="#9CA3AF"
              />
              <YAxis
                tick={{ fontSize: 11 }}
                stroke="#9CA3AF"
                label={{
                  value: "Trips",
                  angle: -90,
                  position: "insideLeft",
                  style: { fontSize: 11 },
                }}
              />
              <Tooltip
                contentStyle={{
                  fontSize: 12,
                  borderRadius: 8,
                  border: "1px solid #E5E7EB",
                }}
              />
              <Legend wrapperStyle={{ fontSize: 11 }} />
              <Bar
                dataKey="pickups"
                fill="#3B82F6"
                name="Pickups"
                radius={[4, 4, 0, 0]}
              />
              <Bar
                dataKey="returns"
                fill="#10B981"
                name="Returns"
                radius={[4, 4, 0, 0]}
              />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Insights */}
      <div className="px-4 pb-4">
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-3">
          <div className="flex items-start gap-2">
            <TrendingUp className="w-4 h-4 text-blue-600 mt-0.5" />
            <div className="flex-1">
              <p className="text-sm text-blue-900 mb-1">
                Peak Imbalance Detected
              </p>
              <p className="text-xs text-blue-700">
                Stockout rates highest at 8-9am (6.8%) and 6pm
                (7.2%). Consider pre-positioning bikes at
                high-demand stations before these windows.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}