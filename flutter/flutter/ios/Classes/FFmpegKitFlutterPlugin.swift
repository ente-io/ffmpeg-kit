// Copyright (c) 2018-2022 Taner Sener
//
// This file is part of FFmpegKit.
//
// FFmpegKit is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// FFmpegKit is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with FFmpegKit.  If not, see <http://www.gnu.org/licenses/>.

import Flutter
import Foundation
import ffmpegkit

// Constants
private let platformName = "ios"
private let methodChannelId = "flutter.arthenica.com/ffmpeg_kit"
private let eventChannelId = "flutter.arthenica.com/ffmpeg_kit_event"

// Log Class Keys
private let keyLogSessionId = "sessionId"
private let keyLogLevel = "level"
private let keyLogMessage = "message"

// Statistics Class Keys
private let keyStatisticsSessionId = "sessionId"
private let keyStatisticsVideoFrameNumber = "videoFrameNumber"
private let keyStatisticsVideoFps = "videoFps"
private let keyStatisticsVideoQuality = "videoQuality"
private let keyStatisticsSize = "size"
private let keyStatisticsTime = "time"
private let keyStatisticsBitrate = "bitrate"
private let keyStatisticsSpeed = "speed"

// Session Class Keys
private let keySessionId = "sessionId"
private let keySessionCreateTime = "createTime"
private let keySessionStartTime = "startTime"
private let keySessionCommand = "command"
private let keySessionType = "type"
private let keySessionMediaInformation = "mediaInformation"

// Session Types
private let sessionTypeFFmpeg = 1
private let sessionTypeFFprobe = 2
private let sessionTypeMediaInformation = 3

// Events
private let eventLogCallbackEvent = "FFmpegKitLogCallbackEvent"
private let eventStatisticsCallbackEvent = "FFmpegKitStatisticsCallbackEvent"
private let eventCompleteCallbackEvent = "FFmpegKitCompleteCallbackEvent"

// Argument Names
private let argumentSessionId = "sessionId"
private let argumentWaitTimeout = "waitTimeout"
private let argumentArguments = "arguments"
private let argumentFfprobeJsonOutput = "ffprobeJsonOutput"

public class FFmpegKitFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var logsEnabled: Bool = false
  private var statisticsEnabled: Bool = false
  private let asyncDispatchQueue = DispatchQueue.global(qos: .default)

  override init() {
    super.init()
    print("FFmpegKitFlutterPlugin created.")
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    print("FFmpegKitFlutterPlugin started listening to events.")
    registerGlobalCallbacks()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(
      name: methodChannelId, binaryMessenger: registrar.messenger())
    let eventChannel = FlutterEventChannel(
      name: eventChannelId, binaryMessenger: registrar.messenger())
    let instance = FFmpegKitFlutterPlugin()

    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  private func registerGlobalCallbacks() {
    FFmpegKitConfig.enableFFmpegSessionCompleteCallback { [weak self] session in
      guard let self = self, let dictionary = Self.toSessionDictionary(session: session) else {
        return
      }
      DispatchQueue.main.async {
        self.eventSink?([eventCompleteCallbackEvent: dictionary])
      }
    }

    FFmpegKitConfig.enableFFprobeSessionCompleteCallback { [weak self] session in
      guard let self = self, let dictionary = Self.toSessionDictionary(session: session) else {
        return
      }
      DispatchQueue.main.async {
        self.eventSink?([eventCompleteCallbackEvent: dictionary])
      }
    }

    FFmpegKitConfig.enableMediaInformationSessionCompleteCallback { [weak self] session in
      guard let self = self, let dictionary = Self.toSessionDictionary(session: session) else {
        return
      }
      DispatchQueue.main.async {
        self.eventSink?([eventCompleteCallbackEvent: dictionary])
      }
    }

    FFmpegKitConfig.enableLogCallback { [weak self] log in
      guard let self = self, self.logsEnabled, let dictionary = Self.toLogDictionary(log: log)
      else { return }
      DispatchQueue.main.async {
        self.eventSink?([eventLogCallbackEvent: dictionary])
      }
    }

    FFmpegKitConfig.enableStatisticsCallback { [weak self] statistics in
      guard let self = self, self.statisticsEnabled,
        let dictionary = Self.toStatisticsDictionary(statistics: statistics)
      else { return }
      DispatchQueue.main.async {
        self.eventSink?([eventStatisticsCallbackEvent: dictionary])
      }
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let sessionId = arguments?[argumentSessionId] as? NSNumber
    let waitTimeout = arguments?[argumentWaitTimeout] as? NSNumber
    let argumentsArray = arguments?[argumentArguments] as? [Any]
    let ffprobeJsonOutput = arguments?[argumentFfprobeJsonOutput] as? String

    switch call.method {
    case "abstractSessionGetEndTime":
      if let id = sessionId {
        abstractSessionGetEndTime(sessionId: id, result: result)
      } else {
        result(FlutterError(code: "INVALID_SESSION", message: "Invalid session id.", details: nil))
      }

    case "abstractSessionGetDuration":
      if let id = sessionId {
        abstractSessionGetDuration(sessionId: id, result: result)
      } else {
        result(FlutterError(code: "INVALID_SESSION", message: "Invalid session id.", details: nil))
      }

    case "abstractSessionGetAllLogs":
      if let id = sessionId {
        abstractSessionGetAllLogs(sessionId: id, timeout: waitTimeout, result: result)
      } else {
        result(FlutterError(code: "INVALID_SESSION", message: "Invalid session id.", details: nil))
      }

    case "ffmpegSession":
      if let args = argumentsArray {
        ffmpegSession(arguments: args, result: result)
      } else {
        result(
          FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments array.", details: nil)
        )
      }

    case "ffprobeSession":
      if let args = argumentsArray {
        ffprobeSession(arguments: args, result: result)
      } else {
        result(
          FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments array.", details: nil)
        )
      }

    case "mediaInformationSession":
      if let args = argumentsArray {
        mediaInformationSession(arguments: args, result: result)
      } else {
        result(
          FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments array.", details: nil)
        )
      }

    case "getMediaInformation":
      if let id = sessionId {
        getMediaInformation(sessionId: id, result: result)
      } else {
        result(FlutterError(code: "INVALID_SESSION", message: "Invalid session id.", details: nil))
      }

    case "mediaInformationJsonParserFrom":
      if let json = ffprobeJsonOutput {
        mediaInformationJsonParserFrom(ffprobeJsonOutput: json, result: result)
      } else {
        result(
          FlutterError(
            code: "INVALID_FFPROBE_JSON_OUTPUT", message: "Invalid ffprobe json output.",
            details: nil))
      }

    case "enableLogs":
      updateLogsEnabled(enabled: false, result: result)

    case "disableLogs":
      updateLogsEnabled(enabled: false, result: result)

    case "enableStatistics":
      updateStatisticsEnabled(enabled: true, result: result)

    case "disableStatistics":
      updateStatisticsEnabled(enabled: false, result: result)

    case "getPlatform":
      getPlatform(result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Session Methods
  private func abstractSessionGetEndTime(sessionId: NSNumber, result: @escaping FlutterResult) {
    guard let session = FFmpegKitConfig.getSession(sessionId.intValue) as? AbstractSession else {
      result(FlutterError(code: "SESSION_NOT_FOUND", message: "Session not found.", details: nil))
      return
    }
    if let endTime = session.getEndTime() {
      result(NSNumber(value: Int64(endTime.timeIntervalSince1970 * 1000)))
    } else {
      result(nil)
    }
  }

  private func abstractSessionGetDuration(sessionId: NSNumber, result: @escaping FlutterResult) {
    guard let session = FFmpegKitConfig.getSession(sessionId.intValue) as? AbstractSession else {
      result(FlutterError(code: "SESSION_NOT_FOUND", message: "Session not found.", details: nil))
      return
    }
    result(NSNumber(value: session.getDuration()))
  }

  private func abstractSessionGetAllLogs(
    sessionId: NSNumber, timeout: NSNumber?, result: @escaping FlutterResult
  ) {
    guard let session = FFmpegKitConfig.getSession(sessionId.intValue) as? AbstractSession else {
      result(FlutterError(code: "SESSION_NOT_FOUND", message: "Session not found.", details: nil))
      return
    }
    let timeoutValue =
      Self.isValidPositiveNumber(value: timeout)
      ? timeout!.int32Value : AbstractSessionDefaultTimeoutForAsynchronousMessagesInTransmit
    let allLogs = session.getAllLogs(withTimeout: timeoutValue)
    result(Self.toLogArray(logs: allLogs))
  }

  private func ffmpegSession(arguments: [Any], result: @escaping FlutterResult) {
    let session = FFmpegSession.create(
      arguments, withCompleteCallback: nil, withLogCallback: nil, withStatisticsCallback: nil,
      with: .neverPrintLogs)
    result(Self.toSessionDictionary(session: session))
  }

  private func ffprobeSession(arguments: [Any], result: @escaping FlutterResult) {
    let session = FFprobeSession.create(
      arguments, withCompleteCallback: nil, withLogCallback: nil,
      with: .neverPrintLogs)
    result(Self.toSessionDictionary(session: session))
  }

  private func mediaInformationSession(arguments: [Any], result: @escaping FlutterResult) {
    let session = MediaInformationSession.create(
      arguments, withCompleteCallback: nil, withLogCallback: nil)
    result(Self.toSessionDictionary(session: session))
  }

  private func getMediaInformation(sessionId: NSNumber, result: @escaping FlutterResult) {
    guard let session = FFmpegKitConfig.getSession(sessionId.intValue) as? AbstractSession else {
      result(FlutterError(code: "SESSION_NOT_FOUND", message: "Session not found.", details: nil))
      return
    }
    if session.isMediaInformation() {
      let mediaSession = session as! MediaInformationSession
      result(
        Self.toMediaInformationDictionary(mediaInformation: mediaSession.getMediaInformation()))
    } else {
      result(
        FlutterError(
          code: "NOT_MEDIA_INFORMATION_SESSION",
          message: "A session is found but it does not have the correct type.", details: nil))
    }
  }

  private func mediaInformationJsonParserFrom(
    ffprobeJsonOutput: String, result: @escaping FlutterResult
  ) {
    do {
      let mediaInformation = try MediaInformationJsonParser.fromWithError(ffprobeJsonOutput)
      result(Self.toMediaInformationDictionary(mediaInformation: mediaInformation))
    } catch {
      print("Parsing MediaInformation failed: $error)")
      result(nil)
    }
  }

  // MARK: - Configuration Methods

  private func updateLogsEnabled(
    enabled: Bool,
    result: @escaping FlutterResult
  ) {
    logsEnabled = enabled
    result(nil)
  }

  private func updateStatisticsEnabled(
    enabled: Bool,
    result: @escaping FlutterResult
  ) {
    statisticsEnabled = enabled
    result(nil)
  }

  private func getPlatform(result: @escaping FlutterResult) {
    result(platformName)
  }

  // MARK: - Helper Methods for Data Conversion

  static func toSessionDictionary(session: Session?) -> [String: Any]? {
    guard let session = session else { return nil }
    var dictionary: [String: Any] = [
      keySessionId: NSNumber(value: session.getId()),
      keySessionCreateTime: NSNumber(
        value: Int64(session.getCreateTime().timeIntervalSince1970 * 1000)),
      keySessionStartTime: NSNumber(
        value: Int64(session.getStartTime().timeIntervalSince1970 * 1000)),
      keySessionCommand: session.getCommand(),
    ]

    if session.isFFmpeg() {
      dictionary[keySessionType] = NSNumber(value: sessionTypeFFmpeg)
    } else if session.isFFprobe() {
      dictionary[keySessionType] = NSNumber(value: sessionTypeFFprobe)
    } else if session.isMediaInformation() {
      let mediaSession = session as! MediaInformationSession
      dictionary[keySessionMediaInformation] = toMediaInformationDictionary(
        mediaInformation: mediaSession.getMediaInformation())
      dictionary[keySessionType] = NSNumber(value: sessionTypeMediaInformation)
    }

    return dictionary
  }

  static func toLogDictionary(log: Log?) -> [String: Any]? {
    guard let log = log else { return nil }
    return [
      keyLogSessionId: NSNumber(value: log.getSessionId()),
      keyLogLevel: NSNumber(value: log.getLevel()),
      keyLogMessage: log.getMessage(),
    ]
  }

  static func toStatisticsDictionary(statistics: Statistics?) -> [String: Any]? {
    guard let statistics = statistics else { return nil }
    return [
      keyStatisticsSessionId: NSNumber(value: statistics.getSessionId()),
      keyStatisticsVideoFrameNumber: NSNumber(value: statistics.getVideoFrameNumber()),
      keyStatisticsVideoFps: NSNumber(value: statistics.getVideoFps()),
      keyStatisticsVideoQuality: NSNumber(value: statistics.getVideoQuality()),
      keyStatisticsSize: NSNumber(value: statistics.getSize()),
      keyStatisticsTime: NSNumber(value: statistics.getTime()),
      keyStatisticsBitrate: NSNumber(value: statistics.getBitrate()),
      keyStatisticsSpeed: NSNumber(value: statistics.getSpeed()),
    ]
  }

  static func toMediaInformationDictionary(mediaInformation: MediaInformation?) -> [String: Any]? {
    guard let mediaInformation = mediaInformation else { return nil }
    var dictionary: [String: Any] = [:]
    if let properties = mediaInformation.getAllProperties() {
      for (key, value) in properties {
        dictionary[key as! String] = value
      }
    }
    return dictionary
  }

  static func toLogArray(logs: [Any]) -> [[String: Any]] {
    return logs.compactMap { log in
      toLogDictionary(log: log as? Log)
    }
  }

  static func isValidPositiveNumber(value: NSNumber?) -> Bool {
    guard let value = value else { return false }
    return value.intValue >= 0
  }
}
