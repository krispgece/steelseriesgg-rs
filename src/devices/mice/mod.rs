//! Mouse support.
//!
//! Only the Modern family of the community rivalcfg project is covered (see [`modern`]). Prime and Prime+,
//! the older Rival, Sensei and Kana families and the older wireless families use other command sets and are
//! not implemented. Only the colour command has been run on hardware: one colour on all three zones of a wired
//! Rival 3 Gen 2 (owner, 2026-11-16).

pub mod dpi_tables;
pub mod modern;

use super::Device;
use crate::rgb::Color;
use crate::{Error, Result};

/// The error a [`Mouse`] method answers on a model whose protocol has no verified frame for it.
pub(crate) fn unsupported(what: &str, model: &str) -> Error {
    Error::DeviceCommunication(format!("{what} is not supported on {model}"))
}

/// [EXPERIMENTAL] What a wired mouse answered to one setting frame. GG's capture of a wired Rival 3 Gen 2 shows
/// every setting echoed as `<opcode> 00`, zero padded to 64 bytes; what another status byte means is unknown.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SettingAck {
    /// A report starting with the frame's opcode came back; `status` is the byte after the opcode.
    Echoed { opcode: u8, status: u8 },
    /// No such report came back in time, or reading failed. The frame was sent all the same.
    NoReply,
}

/// [EXPERIMENTAL] The answer to the polling-rate read-back (`AB`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PollRateReadback {
    /// The reply as read: the first report starting with the echoed `AB`, or the first report read when none did.
    pub reply: Vec<u8>,
    /// The rate the reply names, `None` for a reply without the echoed `AB` or a level outside the known table.
    pub hz: Option<u16>,
}

/// Trait for mouse-specific functionality. Every setting here is applied to the running mouse only; nothing
/// is saved to its on-board memory.
pub trait Mouse: Device {
    /// Set the DPI of the active stage. Rejects a value outside the model's range or between its steps.
    fn set_dpi(&mut self, dpi: u16) -> Result<()>;

    /// [EXPERIMENTAL] Set 1 to 5 DPI stages, the ones the mouse's DPI button cycles through, and make stage `active`
    /// (0-based) the running one; both axes get the same DPI. Rejects a value outside the model's range or between
    /// its steps.
    fn set_dpi_stages(&mut self, _stages: &[u16], _active: u8) -> Result<()> {
        Err(unsupported("setting DPI stages", &self.info().name))
    }

    /// Set the USB polling rate in Hz (125, 250, 500 or 1000).
    fn set_poll_rate(&mut self, hz: u16) -> Result<()>;

    /// Set every LED zone to one steady colour.
    fn set_color(&mut self, color: Color) -> Result<()>;

    /// [EXPERIMENTAL] Set one LED zone (0-based, below the model's zone count) to a steady colour; only that zone's
    /// frame is sent.
    fn set_zone_color(&mut self, _zone: u8, _color: Color) -> Result<()> {
        Err(unsupported("setting one LED zone", &self.info().name))
    }

    /// Battery level (0-100), or `None` for a model without a battery or a reply that cannot be read.
    fn battery_level(&mut self) -> Result<Option<u8>>;

    /// [EXPERIMENTAL] Firmware version from a read-only query, or `None` when no reply carrying one came back.
    fn firmware_version(&mut self) -> Result<Option<String>> {
        Err(unsupported("reading the firmware version", &self.info().name))
    }

    /// [EXPERIMENTAL] The polling rate the mouse reports for a read-only query, or `None` when no reply came back.
    fn poll_rate_readback(&mut self) -> Result<Option<PollRateReadback>> {
        Err(unsupported("reading the polling rate back", &self.info().name))
    }

    /// [EXPERIMENTAL] What the mouse answered to each frame of the last setting, in the order sent. Empty when
    /// the connection reads no answer (a 2.4 GHz receiver) or nothing has been set yet.
    fn last_acknowledgements(&self) -> &[SettingAck] {
        &[]
    }
}
