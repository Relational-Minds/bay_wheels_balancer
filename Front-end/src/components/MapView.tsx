import React, { useState } from 'react';
import ReactMapGL, { Marker, Popup, NavigationControl } from 'react-map-gl';
import type { MapRef, ViewState } from 'react-map-gl';
import { MapPin, Layers, X } from 'lucide-react';
import 'mapbox-gl/dist/mapbox-gl.css';

type Station = {
  id: number;
  name: string;
  lat: number;
  lng: number;
  capacity: number;
  available: number;
  status: 'critical' | 'warning' | 'balanced' | string;
  type: 'empty' | 'full' | null;
};

// Mock station data for Bay Area
const stations: Station[] = [
  { id: 1, name: 'Market St at 10th St', lat: 37.7764, lng: -122.4172, capacity: 35, available: 3, status: 'critical', type: 'empty' },
  { id: 2, name: 'Berry St at 4th St', lat: 37.7757, lng: -122.3934, capacity: 23, available: 22, status: 'critical', type: 'full' },
  { id: 3, name: 'Powell St BART', lat: 37.7844, lng: -122.4079, capacity: 19, available: 8, status: 'balanced', type: null },
  { id: 4, name: 'Embarcadero at Sansome', lat: 37.8003, lng: -122.4034, capacity: 27, available: 15, status: 'balanced', type: null },
  { id: 5, name: 'Steuart St at Market St', lat: 37.7943, lng: -122.3943, capacity: 23, available: 2, status: 'critical', type: 'empty' },
  { id: 6, name: 'Howard St at Beale St', lat: 37.7915, lng: -122.3965, capacity: 19, available: 18, status: 'warning', type: 'full' },
  { id: 7, name: 'Spear St at Folsom St', lat: 37.7905, lng: -122.3932, capacity: 19, available: 11, status: 'balanced', type: null },
  { id: 8, name: 'San Francisco Caltrain', lat: 37.7764, lng: -122.3943, capacity: 27, available: 1, status: 'critical', type: 'empty' },
  { id: 9, name: 'Townsend St at 7th St', lat: 37.7712, lng: -122.4024, capacity: 15, available: 14, status: 'warning', type: 'full' },
  { id: 10, name: 'Market St at Sansome St', lat: 37.7892, lng: -122.4012, capacity: 27, available: 13, status: 'balanced', type: null },
  { id: 11, name: 'Clay St at Battery St', lat: 37.7951, lng: -122.4005, capacity: 15, available: 8, status: 'balanced', type: null },
  { id: 12, name: 'Washington St at Kearny St', lat: 37.7956, lng: -122.4045, capacity: 15, available: 2, status: 'critical', type: 'empty' },
  { id: 13, name: 'Grant Ave at Columbus Ave', lat: 37.7983, lng: -122.4067, capacity: 23, available: 19, status: 'warning', type: 'full' },
  { id: 14, name: 'Broadway at Battery St', lat: 37.7989, lng: -122.4012, capacity: 15, available: 7, status: 'balanced', type: null },
  { id: 15, name: 'Jackson St at Drumm St', lat: 37.7965, lng: -122.3967, capacity: 15, available: 14, status: 'warning', type: 'full' },
];

const MAPBOX_TOKEN = import.meta.env.VITE_MAPBOX_TOKEN;

const initialViewState: ViewState = {
  latitude: 37.7951,
  longitude: -122.4005,
  zoom: 14,
};

const getStatusColor = (status: string) => {
  switch (status) {
    case 'critical':
      return '#EF4444';
    case 'warning':
      return '#F59E0B';
    case 'balanced':
      return '#10B981';
    default:
      return '#9CA3AF';
  }
};

const getUtilization = (available: number, capacity: number) => {
  return ((available / capacity) * 100).toFixed(0);
};

export function MapView() {
  const [viewState, setViewState] = useState<ViewState>(initialViewState);
  const [selectedStationId, setSelectedStationId] = useState<number | null>(
    null
  );
  const [hoveredStationId, setHoveredStationId] = useState<number | null>(null);

  const selectedStation = stations.find((s) => s.id === selectedStationId);

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200 h-full flex flex-col">
      {/* Header */}
      <div className="px-4 py-3 border-b border-gray-200 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <MapPin className="w-5 h-5 text-blue-600" />
          <h2 className="text-gray-900">Live Station Map</h2>
        </div>
        <div className="flex items-center gap-2">
          <button
            className="p-1.5 hover:bg-gray-100 rounded-md transition-colors"
            title="Layers"
            // hook this up later if you want basemap / overlay switching
            onClick={() => console.log('Layers clicked')}
          >
            <Layers className="w-4 h-4 text-gray-600" />
          </button>
        </div>
      </div>

      {/* Map */}
      <div className="flex-1 relative">
        <ReactMapGL
          {...viewState}
          width="100%"
          height="100%"
          mapStyle="mapbox://styles/mapbox/light-v11"
          mapboxApiAccessToken={MAPBOX_TOKEN}
          onViewportChange={setViewState}
        >
          {/* zoom / rotate controls */}
          <div className="absolute top-2 right-2 z-10">
            <NavigationControl />
          </div>

          {stations.map((station) => {
            const isSelected = station.id === selectedStationId;
            const isHovered = station.id === hoveredStationId;

            return (
              <Marker
                key={station.id}
                longitude={station.lng} // Mapbox uses [lng, lat]
                latitude={station.lat}
              >
                <div
                  className="relative"
                  onClick={(e) => {
                    e.stopPropagation();
                    setSelectedStationId(station.id);
                  }}
                  onMouseEnter={() => setHoveredStationId(station.id)}
                  onMouseLeave={() => setHoveredStationId((prev) =>
                    prev === station.id ? null : prev
                  )}
                >
                  {/* Marker icon */}
                  <svg
                    width="40"
                    height="40"
                    viewBox="0 0 40 40"
                    className="cursor-pointer transition-transform hover:scale-110"
                    style={{
                      filter: isSelected
                        ? 'drop-shadow(0 0 8px rgba(59, 130, 246, 0.8))'
                        : 'drop-shadow(0 2px 4px rgba(0,0,0,0.3))',
                    }}
                  >
                    <circle
                      cx="20"
                      cy="20"
                      r="16"
                      fill={getStatusColor(station.status)}
                      stroke="white"
                      strokeWidth="3"
                    />
                    <text
                      x="20"
                      y="25"
                      textAnchor="middle"
                      fill="white"
                      fontSize="14"
                      fontWeight="bold"
                    >
                      {station.available}
                    </text>
                  </svg>

                  {/* Hover tooltip (small) */}
                  {isHovered && !isSelected && (
                    <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 bg-gray-900 text-white rounded-lg shadow-lg px-3 py-2 whitespace-nowrap z-50 pointer-events-none">
                      <div className="text-xs">
                        <div className="font-medium mb-1">{station.name}</div>
                        <div className="text-gray-300">
                          {station.available} / {station.capacity} bikes
                          available
                        </div>
                      </div>
                      <div className="absolute top-full left-1/2 -translate-x-1/2 -mt-px">
                        <div className="border-4 border-transparent border-t-gray-900" />
                      </div>
                    </div>
                  )}
                </div>
              </Marker>
            );
          })}

          {/* Info popup like your screenshot */}
          {selectedStation && (
            <Popup
              longitude={selectedStation.lng}
              latitude={selectedStation.lat}
              closeButton={false}
              closeOnClick={false}
              anchor="bottom"
              className="!p-0 !bg-transparent !border-none"
            >
              <div className="bg-white rounded-lg shadow-xl border border-gray-200 p-4 w-80">
                <div className="space-y-3">
                  <div className="flex items-start justify-between">
                    <div className="flex-1">
                      <h3 className="text-sm text-gray-900 mb-1">
                        {selectedStation.name}
                      </h3>
                      <span
                        className={`inline-block px-2 py-1 rounded-full text-xs ${
                          selectedStation.status === 'critical'
                            ? 'bg-red-100 text-red-700'
                            : selectedStation.status === 'warning'
                            ? 'bg-yellow-100 text-yellow-700'
                            : 'bg-green-100 text-green-700'
                        }`}
                      >
                        {selectedStation.status === 'critical' &&
                          selectedStation.type === 'empty' &&
                          '⚠️ Running Empty'}
                        {selectedStation.status === 'critical' &&
                          selectedStation.type === 'full' &&
                          '⚠️ Nearly Full'}
                        {selectedStation.status === 'warning' && '⚠ Warning'}
                        {selectedStation.status === 'balanced' && '✓ Balanced'}
                      </span>
                    </div>
                    <button
                      onClick={() => setSelectedStationId(null)}
                      className="text-gray-400 hover:text-gray-600 ml-2 p-1"
                    >
                      <X className="w-4 h-4" />
                    </button>
                  </div>

                  <div className="space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-gray-600">
                        Available Bikes
                      </span>
                      <span
                        className={`text-sm ${
                          selectedStation.status === 'critical' &&
                          selectedStation.type === 'empty'
                            ? 'text-red-600'
                            : 'text-gray-900'
                        }`}
                      >
                        {selectedStation.available} /{' '}
                        {selectedStation.capacity}
                      </span>
                    </div>

                    <div className="flex items-center justify-between">
                      <span className="text-sm text-gray-600">
                        Utilization
                      </span>
                      <span className="text-sm text-gray-900">
                        {getUtilization(
                          selectedStation.available,
                          selectedStation.capacity
                        )}
                        %
                      </span>
                    </div>

                    <div className="w-full bg-gray-200 rounded-full h-2.5">
                      <div
                        className="h-2.5 rounded-full transition-all"
                        style={{
                          width: `${getUtilization(
                            selectedStation.available,
                            selectedStation.capacity
                          )}%`,
                          backgroundColor: getStatusColor(
                            selectedStation.status
                          ),
                        }}
                      />
                    </div>

                    <div className="pt-2 flex items-center justify-between text-xs text-gray-500">
                      <span>Station ID: {selectedStation.id}</span>
                      <span>
                        {selectedStation.lat.toFixed(4)},{' '}
                        {selectedStation.lng.toFixed(4)}
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </Popup>
          )}
        </ReactMapGL>
      </div>

      {/* Legend */}
      <div className="px-4 py-3 border-t border-gray-200 bg-gray-50">
        <div className="flex items-center justify-between text-xs">
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded-full bg-green-500" />
              <span className="text-gray-600">Balanced</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded-full bg-yellow-500" />
              <span className="text-gray-600">Warning</span>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded-full bg-red-500" />
              <span className="text-gray-600">Critical</span>
            </div>
          </div>
          <div className="text-gray-600">
            {stations.filter((s) => s.status === 'critical').length} Critical
            Stations
          </div>
        </div>
      </div>
    </div>
  );
}
