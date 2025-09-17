# Decentralized Property Rental Platform Smart Contract

## Overview

This smart contract implements a comprehensive peer-to-peer property rental platform on the Stacks blockchain. It enables property owners to list their properties for short-term rentals while providing guests with a secure booking and payment system. The platform includes features for property management, booking handling, payment processing, availability tracking, and a review system.

## Features

### Core Functionality
- **Property Management**: Register and manage rental properties with detailed metadata
- **Booking System**: Complete reservation management with automated payment processing
- **Availability Calendar**: Real-time availability tracking and date blocking
- **Review System**: Guest feedback and rating system for properties
- **User Profiles**: Track user activity, reputation, and verification status
- **Payment Escrow**: Secure payment handling with platform commission
- **Administrative Controls**: Platform management and emergency functions

### Key Components
- Property listings with comprehensive details
- Booking records with status tracking
- Date availability matrix
- User review and rating system
- Platform user profiles and verification
- Commission-based payment structure

## Contract Architecture

### Data Structures

#### Property Listings
Each property contains:
- Property owner principal
- Listing title and description
- Geographic location
- Nightly rate in microSTX
- Maximum occupancy
- Operational status
- Booking statistics and ratings

#### Booking Records
Each booking includes:
- Associated property ID
- Guest principal
- Check-in and check-out dates
- Stay duration and payment amount
- Reservation status
- Creation block height

#### User Profiles
User data tracks:
- Number of owned properties
- Completed booking count
- Trust score
- Identity verification status

### Status Constants

#### Property Status
- `property-status-available` (1): Property available for booking
- `property-status-suspended` (2): Property temporarily unavailable

#### Booking Status
- `booking-status-awaiting-confirmation` (1): Pending confirmation
- `booking-status-active-reservation` (2): Confirmed active booking
- `booking-status-stay-completed` (3): Stay completed successfully
- `booking-status-reservation-cancelled` (4): Booking cancelled

## Main Functions

### Property Management

#### `create-property-listing`
```clarity
(create-property-listing 
  (listing-title (string-ascii 100))
  (property-description (string-ascii 500))
  (geographic-location (string-ascii 100))
  (nightly-rate-microstack uint)
  (maximum-occupancy uint))
```
Registers a new property listing on the platform.

**Parameters:**
- `listing-title`: Property title (max 100 characters)
- `property-description`: Detailed description (max 500 characters)
- `geographic-location`: Property location (max 100 characters)
- `nightly-rate-microstack`: Price per night in microSTX
- `maximum-occupancy`: Maximum number of guests

**Returns:** Property ID on success

#### `modify-property-operational-status`
```clarity
(modify-property-operational-status (property-id uint) (updated-status uint))
```
Updates the operational status of a property (available/suspended).

#### `adjust-property-nightly-rate`
```clarity
(adjust-property-nightly-rate (property-id uint) (updated-rate uint))
```
Modifies the nightly rate for a property.

### Booking Management

#### `initiate-property-booking`
```clarity
(initiate-property-booking (property-id uint) (arrival-date uint) (departure-date uint))
```
Creates a new booking reservation with payment processing.

**Process:**
1. Validates property availability and date range
2. Calculates total payment including platform commission
3. Transfers payment to contract escrow
4. Blocks dates in availability calendar
5. Updates booking statistics

**Returns:** Booking ID on success

#### `finalize-booking-checkout`
```clarity
(finalize-booking-checkout (booking-id uint))
```
Completes a booking after the stay period, transferring payment to property owner.

#### `cancel-active-reservation`
```clarity
(cancel-active-reservation (booking-id uint))
```
Cancels an active booking with partial refund (90% after cancellation fee).

### Review System

#### `create-property-review`
```clarity
(create-property-review 
  (property-id uint) 
  (booking-id uint) 
  (numerical-rating uint) 
  (written-feedback (string-ascii 500)))
```
Submits a review and rating for a completed stay.

**Requirements:**
- Must be called by the guest who completed the booking
- Rating must be between 1-5
- Booking must be in completed status
- One review per guest per property

### Availability Management

#### `block-additional-booking-dates`
```clarity
(block-additional-booking-dates 
  (property-id uint) 
  (booking-id uint) 
  (date-one uint) 
  (date-two uint) 
  (date-three uint))
```
Blocks additional dates for extended bookings.

#### `restore-booking-date-availability`
```clarity
(restore-booking-date-availability 
  (property-id uint) 
  (booking-id uint) 
  (date-one uint) 
  (date-two uint) 
  (date-three uint))
```
Restores availability for specified dates (can be called by guest, property owner, or admin).

## Read-Only Functions

### Data Retrieval
- `retrieve-property-details(property-id)`: Get complete property information
- `retrieve-booking-information(booking-id)`: Get booking details
- `retrieve-user-profile-data(user-principal)`: Get user profile data
- `retrieve-property-review(property-id, reviewer-principal)`: Get specific review
- `check-property-date-availability(property-id, date-timestamp)`: Check date availability

### Platform Statistics
- `get-current-commission-rate()`: Current platform commission rate
- `get-total-properties-registered()`: Total number of properties
- `get-total-bookings-created()`: Total number of bookings

## Administrative Functions

### `update-platform-commission-rate`
```clarity
(update-platform-commission-rate (updated-fee-basis-points uint))
```
Updates the platform commission rate (admin only, max 10%).

### `grant-user-verification-status`
```clarity
(grant-user-verification-status (target-user principal))
```
Grants verified status to a user (admin only).

### `execute-emergency-booking-cancellation`
```clarity
(execute-emergency-booking-cancellation (booking-id uint))
```
Emergency cancellation with full refund (admin only).

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 100 | ERR-UNAUTHORIZED-ACCESS | Insufficient permissions |
| 101 | ERR-PROPERTY-DOES-NOT-EXIST | Property not found |
| 102 | ERR-BOOKING-RECORD-NOT-FOUND | Booking not found |
| 103 | ERR-INVALID-DATE-RANGE | Invalid date parameters |
| 104 | ERR-PROPERTY-NOT-AVAILABLE | Property unavailable |
| 105 | ERR-PAYMENT-AMOUNT-INSUFFICIENT | Insufficient payment |
| 106 | ERR-BOOKING-STATUS-INVALID | Invalid booking status |
| 107 | ERR-REVIEW-ALREADY-SUBMITTED | Duplicate review |
| 108 | ERR-RATING-OUT-OF-RANGE | Invalid rating value |
| 109 | ERR-PROPERTY-REGISTRATION-DUPLICATE | Duplicate property |
| 110 | ERR-BOOKING-DEADLINE-EXCEEDED | Past deadline |
| 111 | ERR-INPUT-VALIDATION-FAILED | Invalid input |
| 112 | ERR-STRING-CONTENT-INVALID | Empty string content |

## Payment Structure

### Commission Model
- Default platform commission: 2.5% (250 basis points)
- Commission is automatically deducted from total payment
- Property owner receives: Total Payment - Platform Commission
- Platform retains commission for operational costs

### Cancellation Policy
- Guest-initiated cancellation: 90% refund (10% cancellation fee)
- Emergency admin cancellation: 100% refund
- Cancellations must occur before check-in date

## Security Features

### Input Validation
- Comprehensive validation for all user inputs
- String content verification
- Date range validation
- Principal validity checks
- Numeric range constraints

### Authorization Controls
- Property owner permissions for property management
- Guest permissions for bookings and reviews
- Admin-only functions for platform management
- Multi-role permissions for certain operations

### Payment Security
- Escrow-based payment system
- Automatic payment release after stay completion
- Protected refund mechanisms
- Commission calculation safeguards

## Usage Examples

### Property Registration
```clarity
(contract-call? .rental-platform create-property-listing 
  "Cozy Downtown Apartment" 
  "Beautiful 2-bedroom apartment in the heart of the city with modern amenities" 
  "New York, NY" 
  u50000000 
  u4)
```

### Making a Booking
```clarity
(contract-call? .rental-platform initiate-property-booking 
  u1 
  u1640995200 
  u1641081600)
```

### Submitting a Review
```clarity
(contract-call? .rental-platform create-property-review 
  u1 
  u1 
  u5 
  "Excellent stay! Clean, comfortable, and great location.")
```

## Deployment Considerations

### Prerequisites
- Stacks blockchain testnet/mainnet access
- Sufficient STX for contract deployment
- Understanding of Clarity smart contract language

### Configuration
- Set appropriate commission rate for platform sustainability
- Configure admin principal for platform management
- Consider gas costs for complex operations

### Monitoring
- Track booking success rates
- Monitor payment processing efficiency
- Review user feedback and platform usage metrics